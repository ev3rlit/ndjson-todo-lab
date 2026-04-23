# syntax=docker/dockerfile:1.7

# Build the Linux binary and regenerate templ output inside the image build.
FROM golang:1.25.6-alpine AS build

WORKDIR /src

# Copy dependency metadata first so module download can be cached.
COPY go.mod go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

# Keep the templ CLI version aligned with the repo dependency.
RUN go install github.com/a-h/templ/cmd/templ@v0.3.1001

COPY main.go pages.templ ./

RUN templ generate

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/ndjson-todo-lab .

# Run the compiled binary in a small runtime image.
FROM alpine:3.22 AS runtime

RUN addgroup -S app && adduser -S -G app -h /workspace app

WORKDIR /workspace

# Install only the final application binary into the runtime stage.
COPY --from=build /out/ndjson-todo-lab /usr/local/bin/ndjson-todo-lab

RUN mkdir -p /workspace/data /workspace/logs && chown -R app:app /workspace

USER app

# Match the app defaults to the README's shared-volume layout.
ENV ADDR=:8080
ENV TODO_DATA_FILE=/workspace/data/todos.ndjson

VOLUME ["/workspace/data", "/workspace/logs"]

EXPOSE 8080

CMD ["ndjson-todo-lab"]
