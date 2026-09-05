#!/bin/bash
#
# OCP 관리도구 (octools) - CLI 실행 스크립트
# Linux 환경에서 인터랙티브 CLI 메뉴를 실행한다.
#
# 사용법:
#   chmod +x run_cli.sh
#   ./run_cli.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Python 실행 확인
if command -v python3 &> /dev/null; then
    PYTHON=python3
elif command -v python &> /dev/null; then
    PYTHON=python
else
    echo "Error: Python을 찾을 수 없습니다. Python 3.8+ 설치가 필요합니다."
    exit 1
fi

# oc 명령어 확인
if ! command -v oc &> /dev/null; then
    echo "Warning: oc 명령어를 찾을 수 없습니다."
    echo "  - oc CLI가 설치되어 있는지 확인하세요."
    echo "  - PATH에 oc가 포함되어 있는지 확인하세요."
    echo ""
    read -p "계속 진행하시겠습니까? (y/N): " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        exit 1
    fi
fi

# CLI 실행
cd "$SCRIPT_DIR"
$PYTHON -m cli.main
