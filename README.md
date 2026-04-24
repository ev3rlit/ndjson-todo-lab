# ndjson-todo-lab

## 소개

`Go + templ + nginx + NDJSON + slog`로 구성하는 실습용 Todo 웹 애플리케이션입니다.

레포는 모노레포로 정리되어 있습니다. Todo 서비스는 `apps/todo-service`, 발표 자료는 `apps/slides`에서 함께 관리합니다.

이번 실습의 목적은 단순히 앱 하나를 띄우는 것이 아니라, 파일 기반 운영, 로드밸런싱, append-only 데이터 모델, 로그 수집, NFS 백업, 분리 가능한 인프라 레이어를 함께 경험하는 것입니다.

## 목표

- `templ`을 이용해 Go 웹서버를 직접 구성한다.
- `nginx`로 로드밸런싱을 구성한다.
- 리눅스, 컨테이너, 애플리케이션 구성을 모두 스크립트와 파일을 진실 원천으로 관리한다.
- 웹서버의 모든 로그를 수집해서 외부 볼륨과 `NFS`에 보관한다.
- `slog`를 실제로 사용해 운영 로그 구조를 확인한다.
- 요청 로그와 에러 로그는 모두 JSON 포맷으로 기록한다.
- 모든 구성이 나중에 여러 VM으로 분리 가능하도록 레이어 구조를 유지한다.
- 프로젝트 소개와 발표 자료는 `Slidev`로 구성한다.

## 실행 방법

- 앱 로컬 실행: `cd apps/todo-service && go run .`
- 전체 서비스 실행: `docker compose up --build`
- Slidev 개발 서버: `pnpm install && pnpm slides:dev`
- Slidev PPTX export: `pnpm slides:export:pptx`
- VM2 (`con2`, `10.10.10.50`) 구성: `sudo ENV_FILE=./scripts/vm2/vm2.env ./scripts/vm2/setup.sh`
- VM1 (`con1`, `10.10.10.40`) 구성: `sudo ENV_FILE=./scripts/vm1/vm1.env ./scripts/vm1/setup.sh`

## 구조

```text
.
├── apps
│   ├── slides
│   │   ├── package.json
│   │   ├── slides.md
│   │   └── styles
│   └── todo-service
│       ├── Dockerfile
│       ├── go.mod
│       ├── main.go
│       ├── pages.templ
│       └── todos.ndjson
├── docker
├── nginx
├── scripts
├── docker-compose.yml
├── docker-compose.vm1.yml
├── go.work
├── package.json
└── pnpm-workspace.yaml
```

```mermaid
flowchart LR
    user["User"]
    lb["Load Balancer"]

    subgraph service_vm["VM 1 : Go + templ 서비스"]
        web1["web1"]
        web2["web2"]
        web3["web3"]
        ndjson["todos.ndjson\n(shared volume)"]
        logs["slog JSON logs\nstdout -> collected logs"]
    end

    subgraph backup_vm["VM 2 : 백업"]
        cron["crontab + rsync"]
        nfs["NFS"]
    end

    user --> lb
    lb --> web1
    lb --> web2
    lb --> web3

    web1 --> ndjson
    web2 --> ndjson
    web3 --> ndjson

    web1 --> logs
    web2 --> logs
    web3 --> logs

    ndjson --> cron
    logs --> cron
    cron --> nfs
```
