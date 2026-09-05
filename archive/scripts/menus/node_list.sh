#!/bin/bash
#
# Node 상태 조회
# 사용: ./node_list.sh [namespace] [output_mode]
#   (namespace는 무시됨, Node는 클러스터 리소스)
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

MODE="${2:-color}"
FILTER=$(get_output_filter "$MODE")

# Node 상태 + Role + Version 출력
oc get nodes -o wide 2>&1 | $FILTER
exit ${PIPESTATUS[0]}
