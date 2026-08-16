#!/bin/bash
#
# Service 조회
# 사용: ./svc_list.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

NS="${1:-__ALL__}"
MODE="${2:-color}"
NS_OPT=$(build_ns_option "$NS")
FILTER=$(get_output_filter "$MODE")

oc get svc $NS_OPT 2>&1 | $FILTER
exit ${PIPESTATUS[0]}
