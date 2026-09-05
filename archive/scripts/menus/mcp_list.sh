#!/bin/bash
#
# MachineConfigPool 조회
# UPDATED=False 또는 DEGRADED=True 인 항목을 비정상으로 표시
# 사용: ./mcp_list.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

MODE="${2:-color}"
FILTER=$(get_output_filter "$MODE")

# MCP는 기본 highlight_abnormal로도 False/True 패턴 감지 가능
oc get mcp 2>&1 | $FILTER
exit ${PIPESTATUS[0]}
