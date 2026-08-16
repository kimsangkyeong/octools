# OCP 관리도구 (octools)

OpenShift Container Platform(OCP) 클러스터를 CLI 및 웹 UI로 관리하는 도구.

## 구성

| 구성요소 | 환경 | 설명 |
|----------|------|------|
| CLI | Linux | 인터랙티브 터미널 메뉴 기반 oc 명령어 실행 |
| API Server | Linux | FastAPI REST API (Windows UI에서 원격 호출) |
| Web UI | Windows | Streamlit 기반 웹 인터페이스 |

## 빠른 시작

### Linux CLI (직접 실행)

```bash
cd /opt/octools
chmod +x run_cli.sh
./run_cli.sh
```

### API 서버 (원격 호출용)

```bash
pip install -r requirements.txt
./run_api.sh
```

### Windows UI

```powershell
pip install -r requirements-ui.txt
streamlit run ui/app.py
```

## 프로젝트 구조

```
octools/
├── scripts/           # Shell Script 기반 메뉴 실행
│   ├── menus.conf     #   메뉴 정의 (텍스트 파일)
│   ├── common.sh      #   공통 함수 라이브러리
│   └── menus/         #   메뉴별 실행 스크립트 (.sh)
├── docs/              # 문서 (요구사항, 아키텍처, 서버 구성 가이드)
├── common/            # Python 공통 모듈 (menus.conf 로더, 스크립트 실행)
├── cli/               # Linux CLI 프로그램
├── api/               # FastAPI REST API 서버
├── ui/                # Streamlit 웹 UI
├── run_cli.sh         # CLI 실행 스크립트
├── run_api.sh         # API 서버 실행 스크립트
├── requirements.txt   # 서버 의존성
└── requirements-ui.txt # UI 의존성
```

## 메뉴 확장

메뉴 추가는 Python 코드 수정 없이 2단계로 완료됩니다.

### 1단계: menus.conf에 항목 추가

```bash
# 형식: ID|메뉴명|스크립트파일|NS필요(Y/N)|카테고리|설명
echo "pod_top|Pod 리소스사용량|pod_top.sh|Y|워크로드|Pod CPU/메모리 사용량" >> scripts/menus.conf
```

### 2단계: Shell Script 작성

`scripts/menus/` 디렉토리에 `.sh` 파일을 생성합니다. bash, awk, grep, sed 등을 자유롭게 조합하여 원하는 출력을 만들 수 있습니다.

```bash
cat > scripts/menus/pod_top.sh << 'EOF'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
check_oc_env

NS_OPT=$(build_ns_option "$1")

# CPU 사용량 기준 상위 20개 Pod 출력
oc adm top pod $NS_OPT --no-headers | sort -k3 -rn | head -20 | highlight_abnormal
EOF

chmod +x scripts/menus/pod_top.sh
```

CLI/API 재시작 없이 즉시 반영됩니다.

### 스크립트 인터페이스 규약

| 인수 | 설명 |
|------|------|
| `$1` | namespace (`__ALL__`=전체, `__NONE__`=해당없음, 또는 namespace명) |
| `$2` | output_mode (`color`=CLI 직접출력, `plain`=API 서버용 태그 출력) |

`common.sh`에서 제공하는 공통 함수:
- `check_oc_env` - oc 설치 및 로그인 확인
- `build_ns_option "$1"` - namespace를 `-A` 또는 `-n <ns>` 옵션으로 변환
- `highlight_abnormal` - 비정상 라인 빨간색 출력 (파이프로 사용)
- `mark_abnormal` - API용 `[ABNORMAL]` 태그 출력 (파이프로 사용)

## 문서

- [요구사항](docs/requirements.md)
- [아키텍처 설계서](docs/architecture.md)
- [서버 구성 가이드](docs/server_setup_guide.md)

## PDF 생성

```bash
# Python 스크립트 사용
python3 docs/generate_pdf.py

# 또는 bash 스크립트 사용
./docs/generate_pdf.sh
```
