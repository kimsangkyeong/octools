# OCP 관리도구 (octools) 아키텍처 설계서

| 항목 | 내용 |
|------|------|
| 문서버전 | v1.1 |
| 작성일 | 2026-08-16 |
| 작성자 | Kiro |

---

## 1. 시스템 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Linux Server (OCP 접속 환경)                    │
│                                                                      │
│  ┌─────────────────┐                                                │
│  │   CLI Program    │  직접 실행 (SSH 접속 후 사용)                    │
│  │   (octools_cli)  │                                                │
│  └────────┬─────────┘                                                │
│           │                                                          │
│           ▼                                                          │
│  ┌─────────────────┐      ┌─────────────────┐                      │
│  │  Command Module  │─────▶│    oc CLI       │                      │
│  │  (oc_commands)   │      │  (subprocess)   │                      │
│  └─────────────────┘      └─────────────────┘                      │
│           ▲                                                          │
│           │                                                          │
│  ┌─────────────────┐                                                │
│  │   FastAPI Server │  REST API (포트: 8000)                         │
│  │   (api_server)   │                                                │
│  └────────┬─────────┘                                                │
│           │                                                          │
└───────────│──────────────────────────────────────────────────────────┘
            │ HTTP/HTTPS
            │
┌───────────┴──────────────────────────────────────────────────────────┐
│                     Windows Client                                     │
│                                                                       │
│  ┌─────────────────┐      ┌─────────────────┐                       │
│  │  Streamlit UI    │─────▶│  API Client     │                       │
│  │  (octools_ui)    │      │  (requests)     │                       │
│  └─────────────────┘      └─────────────────┘                       │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 2. 프로젝트 디렉토리 구조

```
octools/
├── docs/                          # 문서
│   ├── requirements.md            # 요구사항 문서
│   ├── architecture.md            # 아키텍처 설계서
│   ├── server_setup_guide.md      # 서버 구성 가이드
│   ├── generate_pdf.py            # PDF 변환 스크립트
│   └── generate_pdf.sh            # PDF 변환 스크립트 (bash)
│
├── scripts/                       # Shell Script 기반 메뉴 실행
│   ├── menus.conf                 # 메뉴 정의 (텍스트 파일)
│   ├── common.sh                  # 공통 함수 라이브러리
│   └── menus/                     # 메뉴별 실행 스크립트
│       ├── pod_list.sh
│       ├── pod_wide.sh
│       ├── node_list.sh
│       ├── co_list.sh
│       ├── mc_list.sh
│       ├── mcp_list.sh
│       ├── deployment_list.sh
│       ├── svc_list.sh
│       ├── route_list.sh
│       ├── pvc_list.sh
│       ├── event_list.sh
│       └── csr_list.sh
│
├── common/                        # Python 공통 모듈
│   ├── __init__.py
│   ├── menu_config.py             # menus.conf 로더
│   ├── oc_commands.py             # shell script 실행 래퍼
│   └── output_parser.py           # 출력 파싱 (fallback)
│
├── cli/                           # Linux CLI 프로그램
│   ├── __init__.py
│   ├── main.py                    # CLI 진입점
│   ├── menu_renderer.py           # 메뉴 화면 렌더링
│   └── color_output.py            # 컬러 출력 유틸
│
├── ui/                            # Windows Streamlit UI
│   ├── __init__.py
│   ├── app.py                     # Streamlit 앱 진입점
│   └── api_client.py              # REST API 호출 클라이언트
│
├── api/                           # REST API 서버 (Linux)
│   ├── __init__.py
│   ├── server.py                  # FastAPI 서버 메인
│   └── routes.py                  # API 라우트 정의
│
├── requirements.txt               # Python 패키지 의존성 (서버)
├── requirements-ui.txt            # Streamlit UI 의존성
├── run_cli.sh                     # CLI 실행 스크립트
├── run_api.sh                     # API 서버 실행 스크립트
└── README.md                      # 프로젝트 설명
```

---

## 3. 모듈 상세 설계

### 3.1 공통 모듈 (common/)

#### 3.1.1 menu_config.py - 메뉴 설정

메뉴를 딕셔너리 리스트로 정의하여 CLI/UI 양쪽에서 동일하게 사용한다.

```python
# 메뉴 항목 구조
menu_item = {
    "id": "pod_list",              # 고유 ID
    "name": "Pod 조회",            # 표시명
    "command": "oc get pod",       # 실행할 oc 명령어
    "namespace_required": True,    # NS 선택 필요 여부
    "description": "전체/특정 NS의 Pod 목록 조회",
    "category": "워크로드"          # 메뉴 분류
}
```

**확장 방법**: `MENU_ITEMS` 리스트에 딕셔너리를 추가하고, 필요 시 `oc_commands.py`에 커스텀 함수를 등록한다.

#### 3.1.2 oc_commands.py - 명령어 실행 모듈

```python
# 핵심 인터페이스
def execute_oc_command(command: str, namespace: str = None) -> dict:
    """
    oc 명령어 실행 후 결과 반환
    Returns: {
        "success": bool,
        "output": str,        # 명령어 출력 원문
        "lines": list,        # 라인별 분리
        "error": str          # 에러 메시지
    }
    """
```

#### 3.1.3 output_parser.py - 출력 파싱

```python
# 비정상 상태 키워드
ABNORMAL_KEYWORDS = [
    "CrashLoopBackOff", "Error", "ImagePullBackOff",
    "Pending", "Terminating", "NotReady", "Unknown",
    "False",  # ClusterOperator 상태
    "DEGRADED"
]

def is_abnormal_line(line: str) -> bool:
    """라인에 비정상 상태 키워드가 포함되어 있는지 확인"""
```

---

### 3.2 CLI 모듈 (cli/)

#### 3.2.1 메뉴 렌더링 흐름

```
┌───────────────────────────────────────────────┐
│             메인 메뉴 화면                       │
│                                               │
│  ┌─────────────────┬─────────────────┐       │
│  │  [1] Pod 조회    │  [7] Deploy 조회 │       │
│  │  [2] Pod 상세    │  [8] Service 조회│       │
│  │  [3] Node 조회   │  [9] Route 조회  │       │
│  │  [4] CO 조회     │ [10] PVC 조회    │       │
│  │  [5] MC 조회     │ [11] Event 조회  │       │
│  │  [6] MCP 조회    │ [12] CSR 조회    │       │
│  └─────────────────┴─────────────────┘       │
│                                               │
│  [←] 이전 페이지  [→] 다음 페이지  [q] 종료    │
└───────────────────────────────────────────────┘
         │
         ▼ (NS 필요 메뉴 선택 시)
┌───────────────────────────────────────────────┐
│             서브 메뉴 (NS 선택)                  │
│                                               │
│  Namespace를 선택하세요:                        │
│  [0] 전체 (All Namespaces)                     │
│  [1] openshift-apiserver                      │
│  [2] openshift-authentication                 │
│  [3] openshift-console                        │
│  ...                                          │
│                                               │
│  [Enter] 선택  [b] 뒤로가기                     │
└───────────────────────────────────────────────┘
         │
         ▼
┌───────────────────────────────────────────────┐
│             결과 출력 화면                       │
│                                               │
│  NAME          READY  STATUS    RESTARTS  AGE │
│  nginx-abc     1/1    Running   0         5d  │
│  redis-xyz     0/1    Error     5         2d  │ ← 빨강색
│  app-123       1/1    Running   0         1d  │
│                                               │
│  [Enter] 메인메뉴로  [q] 종료                   │
└───────────────────────────────────────────────┘
```

#### 3.2.2 화면 이분할 로직

```python
# 페이지당 표시할 메뉴 수 계산
ITEMS_PER_COLUMN = 6          # 한 열에 표시할 항목 수
COLUMNS = 2                    # 열 개수
ITEMS_PER_PAGE = ITEMS_PER_COLUMN * COLUMNS  # 페이지당 12개

# 페이지 계산
total_pages = math.ceil(len(menu_items) / ITEMS_PER_PAGE)
current_page_items = menu_items[page * ITEMS_PER_PAGE : (page+1) * ITEMS_PER_PAGE]
```

---

### 3.3 API 서버 (api/)

#### 3.3.1 API 엔드포인트 설계

| Method | Endpoint | 설명 |
|--------|----------|------|
| GET | `/api/health` | 서버 상태 확인 |
| GET | `/api/menus` | 메뉴 목록 조회 |
| POST | `/api/execute` | oc 명령어 실행 |
| GET | `/api/namespaces` | Namespace 목록 조회 |

#### 3.3.2 API 요청/응답 형식

**POST /api/execute**
```json
// Request
{
    "menu_id": "pod_list",
    "namespace": "openshift-console"  // optional
}

// Response
{
    "success": true,
    "command": "oc get pod -n openshift-console",
    "output": "NAME  READY  STATUS ...",
    "lines": [
        {"text": "NAME  READY  STATUS  RESTARTS  AGE", "abnormal": false},
        {"text": "console-abc  1/1  Running  0  5d", "abnormal": false},
        {"text": "auth-xyz  0/1  Error  3  2d", "abnormal": true}
    ]
}
```

---

### 3.4 Streamlit UI (ui/)

#### 3.4.1 UI 레이아웃

```
┌─────────────────────────────────────────────────────────────┐
│  OCP 관리도구 (octools)                          [서버상태: ●] │
├─────────────────────────┬───────────────────────────────────┤
│                         │                                    │
│  📂 워크로드             │   실행 결과                         │
│  ├─ Pod 조회            │                                    │
│  ├─ Pod 상세            │   NAME    READY  STATUS   AGE      │
│  ├─ Deployment 조회     │   nginx   1/1    Running  5d       │
│  │                      │   redis   0/1    Error    2d  ←빨강│
│  📂 클러스터             │                                    │
│  ├─ Node 조회           │                                    │
│  ├─ CO 조회             │                                    │
│  ├─ MC 조회             │                                    │
│  ├─ MCP 조회            │                                    │
│  │                      │                                    │
│  📂 네트워크             │                                    │
│  ├─ Service 조회        │                                    │
│  ├─ Route 조회          │                                    │
│  │                      │                                    │
│  📂 스토리지             │                                    │
│  ├─ PVC 조회            │                                    │
│  │                      │                                    │
│  📂 기타                 │                                    │
│  ├─ Event 조회          │                                    │
│  ├─ CSR 조회            │                                    │
│                         │                                    │
├─────────────────────────┴───────────────────────────────────┤
│  Namespace: [All ▼]  |  마지막 실행: 2026-08-16 10:30:00     │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. 기술 스택

| 구분 | 기술 | 버전 | 용도 |
|------|------|------|------|
| 언어 | Python | 3.8+ | 전체 |
| 언어 | Bash | - | 실행 스크립트 |
| CLI | curses | stdlib | 터미널 메뉴 UI |
| API | FastAPI | 0.104+ | REST API 서버 |
| API | uvicorn | 0.24+ | ASGI 서버 |
| UI | Streamlit | 1.28+ | 웹 UI 프레임워크 |
| HTTP | requests | 2.31+ | API 호출 |
| 프로세스 | subprocess | stdlib | oc 명령어 실행 |

---

## 5. 데이터 흐름

### 5.1 CLI 실행 흐름

```
사용자 입력 → 메뉴 선택 → NS 필요? ─Yes─→ NS 목록 조회 → NS 선택
                                    │                         │
                                    No                        │
                                    │                         │
                                    ▼                         ▼
                              명령어 조립 ←────────────────────┘
                                    │
                                    ▼
                              subprocess 실행
                                    │
                                    ▼
                              출력 파싱 (비정상 라인 감지)
                                    │
                                    ▼
                              컬러 출력 (빨강 강조)
```

### 5.2 UI 실행 흐름 (원격)

```
사용자 클릭 → 메뉴 선택 → NS 필요? ─Yes─→ API: GET /namespaces → NS 선택
                                    │                              │
                                    No                             │
                                    │                              │
                                    ▼                              ▼
                         API: POST /execute ←─────────────────────┘
                                    │
                                    ▼
                         응답 수신 (JSON)
                                    │
                                    ▼
                         Streamlit 테이블/텍스트 렌더링
                         (비정상 라인 빨강 강조)
```

---

## 6. 확장 가이드 (Shell Script 방식)

### 6.1 새 메뉴 추가 절차

1. `scripts/menus.conf`에 메뉴 항목 한 줄 추가
2. `scripts/menus/` 디렉토리에 해당 `.sh` 파일 생성
3. CLI/API **재시작 없이** 자동 반영 (menus.conf 파일 변경 감지)

```bash
# 1단계: menus.conf에 항목 추가
echo "pod_logs|Pod 로그 조회|pod_logs.sh|Y|워크로드|특정 Pod 로그 출력" >> scripts/menus.conf

# 2단계: shell script 생성
cat > scripts/menus/pod_logs.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
check_oc_env

NS="${1:-__ALL__}"
MODE="${2:-color}"
NS_OPT=$(build_ns_option "$NS")

# Pod 목록에서 선택하여 로그 출력 (커스텀 로직 예시)
oc get pod $NS_OPT --no-headers | awk '{print NR") "$1" ("$3")"}' 
EOF
chmod +x scripts/menus/pod_logs.sh
```

### 6.2 Shell Script 인터페이스 규약

모든 메뉴 스크립트는 다음 규약을 따른다:

| 항목 | 설명 |
|------|------|
| `$1` | namespace (`__ALL__`, `__NONE__`, 또는 namespace명) |
| `$2` | output_mode (`color` = CLI 직접, `plain` = API 서버) |
| stdout | 실행 결과 출력 |
| stderr | 에러 메시지 |
| exit 0 | 성공 |
| exit 1 | 실패 |

### 6.3 plain 모드 출력 규약 (API 서버용)

API 서버에서 호출 시 `$2=plain`으로 전달되며, 스크립트는 다음 태그를 사용:
- `[HEADER]라인내용` → 헤더 라인
- `[ABNORMAL]라인내용` → 비정상 라인 (UI에서 빨간색 표시)
- 태그 없음 → 정상 라인

### 6.4 카테고리 추가

`common/menu_config.py`의 `CATEGORIES` 리스트에 카테고리를 추가하면 UI 사이드바와 CLI 메뉴에 자동 반영된다.

---

## 7. 보안 고려사항

| 항목 | 방안 |
|------|------|
| API 인증 | Bearer Token 기반 인증 헤더 검증 |
| 명령어 인젝션 방지 | 허용된 메뉴 ID만 실행, 직접 명령어 문자열 전달 차단 |
| HTTPS | 운영 환경에서는 TLS 인증서 적용 권장 |
| 접근 제한 | API 서버 방화벽 설정으로 허용 IP만 접근 |

---

## 변경이력

| 버전 | 날짜 | 변경내용 | 작성자 |
|------|------|----------|--------|
| v1.0 | 2026-08-16 | 최초 작성 | Kiro |
| v1.1 | 2026-08-16 | Shell Script 방식으로 메뉴 실행 구조 변경, menus.conf 도입, 확장 가이드 개정 | Kiro |
