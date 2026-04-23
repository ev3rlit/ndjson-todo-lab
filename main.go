package main

import (
	"bufio"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// 애플리케이션 전역 기본값과 이벤트 타입을 한 곳에 모아 둔다.
const (
	defaultAddr      = ":8080"
	defaultDataFile  = "todos.ndjson"
	eventTodoCreated = "todo_created"
	eventTodoChanged = "todo_title_changed"
	eventCompleted   = "todo_completed"
	eventReopened    = "todo_reopened"
	eventDeleted     = "todo_deleted"
)

var logger *slog.Logger

// app은 HTTP 핸들러와 파일 append/replay에 필요한 런타임 의존성을 묶는다.
type app struct {
	dataFile string
	server   serverInfo
	logger   *slog.Logger
	mu       sync.Mutex
}

// todoEvent는 NDJSON 한 줄에 기록되는 이벤트 레코드다.
type todoEvent struct {
	Type      string    `json:"type"`
	ID        string    `json:"id"`
	Title     string    `json:"title,omitempty"`
	TS        time.Time `json:"ts"`
	Server    string    `json:"server"`
	RequestID string    `json:"request_id,omitempty"`
}

// todo는 이벤트 replay 결과로 메모리에서 재구성된 현재 상태다.
type todo struct {
	ID          string
	Title       string
	Completed   bool
	Deleted     bool
	LastUpdated time.Time
}

// todoView는 템플릿 렌더링에 맞게 가공한 화면용 모델이다.
type todoView struct {
	ID          string
	Title       string
	Completed   bool
	UpdatedAt   time.Time
	LastUpdated string
}

// serverInfo는 현재 응답한 서버를 화면과 로그에서 식별하기 위한 값이다.
type serverInfo struct {
	ServerName string
	Hostname   string
	Container  string
	PID        int
	Now        time.Time
}

// pageData는 index 페이지 렌더링에 필요한 모든 데이터를 담는다.
type pageData struct {
	Server         serverInfo
	Todos          []todoView
	ActiveCount    int
	CompletedCount int
	EventFile      string
	LastRequestID  string
	LastReloadedAt string
	ComposerValue  string
	NoticeMessage  string
}

type ctxKey string

const requestIDKey ctxKey = "request_id"

// main은 로거, 서버 식별 정보, 데이터 파일, 라우터를 초기화하고 HTTP 서버를 시작한다.
func main() {
	// 운영 로그는 stdout으로 JSON 하나만 남기도록 맞춘다.
	logger = slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	// todo 이벤트 파일 경로는 환경 변수로 바꿀 수 있게 둔다.
	dataFile := os.Getenv("TODO_DATA_FILE")
	if dataFile == "" {
		dataFile = defaultDataFile
	}

	// 화면과 로그에 같이 쓸 서버 식별 정보를 미리 수집한다.
	server, err := detectServerInfo()
	if err != nil {
		logger.Error("server info detection failed", slog.String("error", err.Error()))
		os.Exit(1)
	}

	app := &app{
		dataFile: dataFile,
		server:   server,
		logger:   logger,
	}

	if err := ensureDataFile(dataFile); err != nil {
		logger.Error("data file init failed", slog.String("error", err.Error()), slog.String("path", dataFile))
		os.Exit(1)
	}

	// 라우팅은 todo 조회, 생성, 상태 전환, 삭제 네 가지로 시작한다.
	mux := http.NewServeMux()
	mux.HandleFunc("GET /", app.handleIndex)
	mux.HandleFunc("POST /todos", app.handleCreateTodo)
	mux.HandleFunc("POST /todos/{id}/toggle", app.handleToggleTodo)
	mux.HandleFunc("POST /todos/{id}/delete", app.handleDeleteTodo)

	// 모든 요청은 공통 request_id와 JSON 요청 로그를 거치게 한다.
	handler := app.requestLoggingMiddleware(mux)
	addr := envOrDefault("ADDR", defaultAddr)

	logger.Info("server starting",
		slog.String("addr", addr),
		slog.String("server", app.server.ServerName),
		slog.String("hostname", app.server.Hostname),
		slog.Int("pid", app.server.PID),
		slog.String("data_file", app.dataFile),
	)

	if err := http.ListenAndServe(addr, handler); err != nil {
		logger.Error("server exited", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

// handleIndex는 NDJSON 전체를 replay한 뒤 현재 todo 상태를 페이지에 렌더링한다.
func (a *app) handleIndex(w http.ResponseWriter, r *http.Request) {
	todos, err := a.replayTodos(r.Context())
	if err != nil {
		a.renderErrorState(w, r, http.StatusInternalServerError, nil, "", "할 일 목록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.", err)
		return
	}

	if err := a.renderIndexPage(w, r, http.StatusOK, todos, "", ""); err != nil {
		http.Error(w, "화면을 보여주지 못했습니다. 잠시 후 다시 시도해 주세요.", http.StatusInternalServerError)
	}
}

// handleCreateTodo는 제목을 받아 생성 이벤트 한 줄을 append한다.
func (a *app) handleCreateTodo(w http.ResponseWriter, r *http.Request) {
	title := strings.TrimSpace(r.FormValue("title"))
	if title == "" {
		todos, _ := a.replayTodos(r.Context())
		a.renderErrorState(w, r, http.StatusBadRequest, todos, title, "할 일 내용을 입력해 주세요.", errors.New("empty title"))
		return
	}

	event := a.newEvent(r, eventTodoCreated, newTodoID(), title)
	if err := a.appendEvent(r.Context(), event); err != nil {
		todos, _ := a.replayTodos(r.Context())
		a.renderErrorState(w, r, http.StatusInternalServerError, todos, title, "할 일을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.", err)
		return
	}

	http.Redirect(w, r, "/", http.StatusSeeOther)
}

// handleToggleTodo는 현재 상태를 replay로 확인한 뒤 완료/복구 이벤트를 결정한다.
func (a *app) handleToggleTodo(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		todos, _ := a.replayTodos(r.Context())
		a.renderErrorState(w, r, http.StatusBadRequest, todos, "", "대상 할 일을 확인하지 못했습니다. 목록에서 다시 시도해 주세요.", errors.New("missing todo id"))
		return
	}

	todos, err := a.replayTodos(r.Context())
	if err != nil {
		a.renderErrorState(w, r, http.StatusInternalServerError, nil, "", "할 일 상태를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.", err)
		return
	}

	current, ok := todos[id]
	if !ok || current.Deleted {
		a.renderErrorState(w, r, http.StatusNotFound, todos, "", "이 할 일을 찾지 못했습니다. 목록을 새로고침한 뒤 다시 시도해 주세요.", fmt.Errorf("todo %s not found", id))
		return
	}

	eventType := eventCompleted
	if current.Completed {
		eventType = eventReopened
	}

	event := a.newEvent(r, eventType, id, current.Title)
	if err := a.appendEvent(r.Context(), event); err != nil {
		a.renderErrorState(w, r, http.StatusInternalServerError, todos, "", "할 일 상태를 바꾸지 못했습니다. 잠시 후 다시 시도해 주세요.", err)
		return
	}

	http.Redirect(w, r, "/", http.StatusSeeOther)
}

// handleDeleteTodo는 대상 todo가 실제로 있는지 확인한 뒤 삭제 이벤트를 append한다.
func (a *app) handleDeleteTodo(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		todos, _ := a.replayTodos(r.Context())
		a.renderErrorState(w, r, http.StatusBadRequest, todos, "", "대상 할 일을 확인하지 못했습니다. 목록에서 다시 시도해 주세요.", errors.New("missing todo id"))
		return
	}

	todos, err := a.replayTodos(r.Context())
	if err != nil {
		a.renderErrorState(w, r, http.StatusInternalServerError, nil, "", "할 일 상태를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.", err)
		return
	}

	current, ok := todos[id]
	if !ok || current.Deleted {
		a.renderErrorState(w, r, http.StatusNotFound, todos, "", "이 할 일을 찾지 못했습니다. 목록을 새로고침한 뒤 다시 시도해 주세요.", fmt.Errorf("todo %s not found", id))
		return
	}

	event := a.newEvent(r, eventDeleted, id, current.Title)
	if err := a.appendEvent(r.Context(), event); err != nil {
		a.renderErrorState(w, r, http.StatusInternalServerError, todos, "", "할 일을 삭제하지 못했습니다. 잠시 후 다시 시도해 주세요.", err)
		return
	}

	http.Redirect(w, r, "/", http.StatusSeeOther)
}

// newEvent는 현재 요청 기준의 공통 메타데이터를 채운 이벤트를 만든다.
func (a *app) newEvent(r *http.Request, eventType, id, title string) todoEvent {
	return todoEvent{
		Type:      eventType,
		ID:        id,
		Title:     title,
		TS:        time.Now().UTC(),
		Server:    a.server.ServerName,
		RequestID: requestIDFromContext(r.Context()),
	}
}

// appendEvent는 이벤트를 NDJSON 한 줄로 직렬화해서 파일 끝에만 추가한다.
func (a *app) appendEvent(ctx context.Context, event todoEvent) error {
	line, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}

	// 같은 프로세스 안에서는 append가 섞이지 않도록 mutex로 보호한다.
	a.mu.Lock()
	defer a.mu.Unlock()

	file, err := os.OpenFile(a.dataFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("open data file: %w", err)
	}
	defer file.Close()

	if _, err := file.Write(append(line, '\n')); err != nil {
		return fmt.Errorf("append event: %w", err)
	}

	a.logger.InfoContext(ctx, "todo appended",
		slog.String("event_type", event.Type),
		slog.String("todo_id", event.ID),
		slog.String("server", a.server.ServerName),
		slog.String("request_id", event.RequestID),
	)

	return nil
}

// renderIndexPage는 같은 레이아웃 안에서 목록과 notice를 함께 렌더링한다.
func (a *app) renderIndexPage(w http.ResponseWriter, r *http.Request, status int, todos map[string]todo, composerValue, noticeMessage string) error {
	data := a.newPageData(r, todos, composerValue, noticeMessage)
	w.WriteHeader(status)
	return IndexPage(data).Render(r.Context(), w)
}

// renderErrorState는 에러 로그를 남기고, 가능한 경우 같은 페이지 안에 notice로 보여 준다.
func (a *app) renderErrorState(w http.ResponseWriter, r *http.Request, status int, todos map[string]todo, composerValue, message string, err error) {
	a.logger.ErrorContext(r.Context(), "request failed",
		slog.String("request_id", requestIDFromContext(r.Context())),
		slog.String("method", r.Method),
		slog.String("path", r.URL.Path),
		slog.Int("status", status),
		slog.String("error", err.Error()),
		slog.String("server", a.server.ServerName),
	)

	if renderErr := a.renderIndexPage(w, r, status, todos, composerValue, message); renderErr != nil {
		a.logger.ErrorContext(r.Context(), "error state render failed",
			slog.String("request_id", requestIDFromContext(r.Context())),
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.String("error", renderErr.Error()),
			slog.String("server", a.server.ServerName),
		)
		http.Error(w, message, status)
	}
}

// replayTodos는 파일 전체를 처음부터 읽어 현재 todo 상태를 다시 만든다.
func (a *app) replayTodos(ctx context.Context) (map[string]todo, error) {
	file, err := os.Open(a.dataFile)
	if err != nil {
		return nil, fmt.Errorf("open data file: %w", err)
	}
	defer file.Close()

	a.logger.InfoContext(ctx, "todo replay started",
		slog.String("path", a.dataFile),
		slog.String("server", a.server.ServerName),
	)

	todos := make(map[string]todo)
	scanner := bufio.NewScanner(file)
	lineNumber := 0

	for scanner.Scan() {
		lineNumber++
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		var event todoEvent
		if err := json.Unmarshal([]byte(line), &event); err != nil {
			return nil, fmt.Errorf("parse event line %d: %w", lineNumber, err)
		}

		if err := applyEvent(todos, event); err != nil {
			return nil, fmt.Errorf("apply event line %d: %w", lineNumber, err)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan data file: %w", err)
	}

	a.logger.InfoContext(ctx, "todo replay finished",
		slog.Int("line_count", lineNumber),
		slog.Int("todo_count", len(todos)),
		slog.String("server", a.server.ServerName),
	)

	return todos, nil
}

// applyEvent는 이벤트 한 건을 현재 projection에 반영한다.
func applyEvent(todos map[string]todo, event todoEvent) error {
	switch event.Type {
	case eventTodoCreated:
		todos[event.ID] = todo{
			ID:          event.ID,
			Title:       event.Title,
			Completed:   false,
			Deleted:     false,
			LastUpdated: event.TS,
		}
	case eventTodoChanged:
		current, ok := todos[event.ID]
		if !ok || current.Deleted {
			return fmt.Errorf("title change on missing todo %s", event.ID)
		}
		current.Title = event.Title
		current.LastUpdated = event.TS
		todos[event.ID] = current
	case eventCompleted:
		current, ok := todos[event.ID]
		if !ok || current.Deleted {
			return fmt.Errorf("complete on missing todo %s", event.ID)
		}
		current.Completed = true
		current.LastUpdated = event.TS
		todos[event.ID] = current
	case eventReopened:
		current, ok := todos[event.ID]
		if !ok || current.Deleted {
			return fmt.Errorf("reopen on missing todo %s", event.ID)
		}
		current.Completed = false
		current.LastUpdated = event.TS
		todos[event.ID] = current
	case eventDeleted:
		current, ok := todos[event.ID]
		if !ok || current.Deleted {
			return fmt.Errorf("delete on missing todo %s", event.ID)
		}
		current.Deleted = true
		current.LastUpdated = event.TS
		todos[event.ID] = current
	default:
		return fmt.Errorf("unknown event type %q", event.Type)
	}

	return nil
}

// projectTodoViews는 내부 상태를 화면용 목록과 집계 값으로 변환한다.
func projectTodoViews(todos map[string]todo) ([]todoView, int, int) {
	views := make([]todoView, 0, len(todos))
	activeCount := 0
	completedCount := 0

	for _, item := range todos {
		if item.Deleted {
			continue
		}
		if item.Completed {
			completedCount++
		} else {
			activeCount++
		}
		views = append(views, todoView{
			ID:          item.ID,
			Title:       item.Title,
			Completed:   item.Completed,
			UpdatedAt:   item.LastUpdated,
			LastUpdated: item.LastUpdated.Local().Format("2006-01-02 15:04:05 MST"),
		})
	}

	sort.Slice(views, func(i, j int) bool {
		return views[i].UpdatedAt.After(views[j].UpdatedAt)
	})

	return views, activeCount, completedCount
}

// newPageData는 현재 todo 상태와 notice를 템플릿 입력 구조로 묶는다.
func (a *app) newPageData(r *http.Request, todos map[string]todo, composerValue, noticeMessage string) pageData {
	views, activeCount, completedCount := projectTodoViews(todos)
	return pageData{
		Server: serverInfo{
			ServerName: a.server.ServerName,
			Hostname:   a.server.Hostname,
			Container:  a.server.Container,
			PID:        a.server.PID,
			Now:        time.Now(),
		},
		Todos:          views,
		ActiveCount:    activeCount,
		CompletedCount: completedCount,
		EventFile:      filepath.Base(a.dataFile),
		LastRequestID:  requestIDFromContext(r.Context()),
		LastReloadedAt: time.Now().Format(time.RFC3339),
		ComposerValue:  composerValue,
		NoticeMessage:  noticeMessage,
	}
}

// ensureDataFile은 시작 전에 이벤트 파일이 없으면 빈 파일을 만들어 둔다.
func ensureDataFile(path string) error {
	file, err := os.OpenFile(path, os.O_CREATE, 0o644)
	if err != nil {
		return fmt.Errorf("create data file: %w", err)
	}
	return file.Close()
}

// detectServerInfo는 화면과 로그에 노출할 서버 식별 정보를 만든다.
func detectServerInfo() (serverInfo, error) {
	hostname, err := os.Hostname()
	if err != nil {
		return serverInfo{}, fmt.Errorf("lookup hostname: %w", err)
	}

	serverName := envOrDefault("SERVER_NAME", hostname)
	container := envOrDefault("CONTAINER_NAME", hostname)

	return serverInfo{
		ServerName: serverName,
		Hostname:   hostname,
		Container:  container,
		PID:        os.Getpid(),
		Now:        time.Now(),
	}, nil
}

// requestLoggingMiddleware는 모든 요청에 request_id를 붙이고 JSON 요청 로그를 남긴다.
func (a *app) requestLoggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := requestIDFromHeader(r)
		ctx := context.WithValue(r.Context(), requestIDKey, requestID)
		r = r.WithContext(ctx)

		start := time.Now()
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(recorder, r)

		a.logger.InfoContext(ctx, "request completed",
			slog.String("request_id", requestID),
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", recorder.status),
			slog.String("remote_addr", remoteAddr(r)),
			slog.Duration("duration", time.Since(start)),
			slog.String("server", a.server.ServerName),
			slog.String("hostname", a.server.Hostname),
			slog.String("container", a.server.Container),
			slog.Int("pid", a.server.PID),
		)
	})
}

// requestIDFromContext는 미들웨어가 넣어 둔 request_id를 꺼낸다.
func requestIDFromContext(ctx context.Context) string {
	if value, ok := ctx.Value(requestIDKey).(string); ok {
		return value
	}
	return "unknown"
}

// requestIDFromHeader는 외부 프록시가 준 request_id를 우선 사용하고, 없으면 새로 만든다.
func requestIDFromHeader(r *http.Request) string {
	if requestID := strings.TrimSpace(r.Header.Get("X-Request-Id")); requestID != "" {
		return requestID
	}
	return randomID("req")
}

// newTodoID는 todo 생성 이벤트에 쓸 식별자를 만든다.
func newTodoID() string {
	return randomID("todo")
}

// randomID는 짧은 랜덤 식별자를 만들고, 실패 시에는 시간 기반 값으로 대체한다.
func randomID(prefix string) string {
	var bytes [6]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return fmt.Sprintf("%s-%d", prefix, time.Now().UnixNano())
	}
	return prefix + "-" + hex.EncodeToString(bytes[:])
}

// envOrDefault는 환경 변수가 비어 있으면 기본값을 돌려준다.
func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

// remoteAddr는 host:port 형식의 RemoteAddr에서 host만 추출한다.
func remoteAddr(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// statusRecorder는 미들웨어에서 최종 응답 상태 코드를 기록하기 위한 래퍼다.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

// WriteHeader는 실제 응답 전에 상태 코드를 별도로 저장해 둔다.
func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}
