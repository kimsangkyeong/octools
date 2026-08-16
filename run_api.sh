#!/bin/bash
#
# OCP 관리도구 (octools) - API 서버 실행 스크립트
# FastAPI REST API 서버를 시작한다.
# Windows Streamlit UI에서 원격으로 oc 명령어를 실행하기 위한 서버.
#
# 사용법:
#   chmod +x run_api.sh
#   ./run_api.sh [포트번호]
#
# 기본 포트: 8000
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=${1:-8000}

# Python 실행 확인
if command -v python3 &> /dev/null; then
    PYTHON=python3
elif command -v python &> /dev/null; then
    PYTHON=python
else
    echo "Error: Python을 찾을 수 없습니다. Python 3.8+ 설치가 필요합니다."
    exit 1
fi

# 의존성 확인
$PYTHON -c "import fastapi" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Error: FastAPI가 설치되지 않았습니다."
    echo "  pip install -r requirements.txt"
    exit 1
fi

$PYTHON -c "import uvicorn" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Error: uvicorn이 설치되지 않았습니다."
    echo "  pip install -r requirements.txt"
    exit 1
fi

# oc 명령어 확인
if ! command -v oc &> /dev/null; then
    echo "Warning: oc 명령어를 찾을 수 없습니다."
    echo "  API 실행은 가능하나, 명령어 실행 시 오류가 발생할 수 있습니다."
fi

echo "==========================================="
echo "  OCP 관리도구 API 서버 시작"
echo "  URL: http://0.0.0.0:${PORT}"
echo "  Docs: http://0.0.0.0:${PORT}/docs"
echo "==========================================="
echo ""

# API 서버 실행
cd "$SCRIPT_DIR"
$PYTHON -m uvicorn api.server:app --host 0.0.0.0 --port $PORT --reload
