#!/bin/bash
#
# MachineConfig 조회
# 사용: ./mc_list.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

MODE="${2:-color}"
FILTER=$(get_output_filter "$MODE")

oc get mc 2>&1 | $FILTER
exit ${PIPESTATUS[0]}
