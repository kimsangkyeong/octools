#!/bin/bash
#
# Namespace 리소스 종합조회
# 선택된 Namespace의 주요 리소스를 한눈에 조회한다.
# Pod, Deployment, Service, DaemonSet, ConfigMap, StatefulSet, Secret
# SA를 사용하는 리소스는 ServiceAccount 정보를 함께 표시한다.
#
# 사용: ./ns_resources.sh <namespace> [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

NS="${1:-__ALL__}"
MODE="${2:-color}"

# namespace 필수 확인
if [ "$NS" = "__ALL__" ] || [ "$NS" = "__NONE__" ]; then
    print_error "Namespace 리소스 종합조회는 특정 Namespace를 선택해야 합니다."
    exit 1
fi

NS_OPT="-n $NS"
FILTER=$(get_output_filter "$MODE")

# ─── Pods (SA 표시) ──────────────────────────────────────────────
print_section "Pods (ServiceAccount 포함)" "$MODE"
pod_output=$(oc get pod $NS_OPT -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,SA:.spec.serviceAccountName,NODE:.spec.nodeName" 2>&1)
if [ $? -eq 0 ]; then
    echo "$pod_output" | $FILTER
else
    echo "$pod_output"
fi

# ─── Deployments (SA 표시) ───────────────────────────────────────
print_section "Deployments (ServiceAccount 포함)" "$MODE"
deploy_output=$(oc get deployment $NS_OPT -o custom-columns="NAME:.metadata.name,READY:.status.readyReplicas,REPLICAS:.spec.replicas,SA:.spec.template.spec.serviceAccountName" 2>&1)
if [ $? -eq 0 ]; then
    echo "$deploy_output" | $FILTER
else
    echo "$deploy_output"
fi

# ─── StatefulSets (SA 표시) ──────────────────────────────────────
print_section "StatefulSets (ServiceAccount 포함)" "$MODE"
sts_output=$(oc get statefulset $NS_OPT -o custom-columns="NAME:.metadata.name,READY:.status.readyReplicas,REPLICAS:.spec.replicas,SA:.spec.template.spec.serviceAccountName" 2>&1)
if [ $? -eq 0 ]; then
    echo "$sts_output" | $FILTER
else
    echo "$sts_output"
fi

# ─── DaemonSets (SA 표시) ────────────────────────────────────────
print_section "DaemonSets (ServiceAccount 포함)" "$MODE"
ds_output=$(oc get daemonset $NS_OPT -o custom-columns="NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady,SA:.spec.template.spec.serviceAccountName" 2>&1)
if [ $? -eq 0 ]; then
    echo "$ds_output" | $FILTER
else
    echo "$ds_output"
fi

# ─── Services ────────────────────────────────────────────────────
print_section "Services" "$MODE"
svc_output=$(oc get svc $NS_OPT 2>&1)
if [ $? -eq 0 ]; then
    echo "$svc_output" | $FILTER
else
    echo "$svc_output"
fi

# ─── ConfigMaps ──────────────────────────────────────────────────
print_section "ConfigMaps" "$MODE"
cm_output=$(oc get cm $NS_OPT 2>&1)
if [ $? -eq 0 ]; then
    echo "$cm_output" | $FILTER
else
    echo "$cm_output"
fi

# ─── Secrets ─────────────────────────────────────────────────────
print_section "Secrets" "$MODE"
secret_output=$(oc get secret $NS_OPT -o custom-columns="NAME:.metadata.name,TYPE:.type,DATA:.data" --no-headers 2>&1 | awk '{print $1, $2}')
if [ $? -eq 0 ]; then
    if [ "$MODE" = "plain" ]; then
        echo "[HEADER]NAME                                     TYPE"
        echo "$secret_output"
    else
        echo -e "${BOLD}${CYAN}NAME                                     TYPE${NC}"
        echo "$secret_output"
    fi
else
    echo "$secret_output"
fi

# ─── ServiceAccounts ─────────────────────────────────────────────
print_section "ServiceAccounts" "$MODE"
sa_output=$(oc get sa $NS_OPT 2>&1)
if [ $? -eq 0 ]; then
    echo "$sa_output" | $FILTER
else
    echo "$sa_output"
fi

# ─── 요약 ────────────────────────────────────────────────────────
echo ""
print_section "리소스 요약 [$NS]" "$MODE"
pod_cnt=$(oc get pod $NS_OPT --no-headers 2>/dev/null | wc -l)
deploy_cnt=$(oc get deployment $NS_OPT --no-headers 2>/dev/null | wc -l)
sts_cnt=$(oc get statefulset $NS_OPT --no-headers 2>/dev/null | wc -l)
ds_cnt=$(oc get daemonset $NS_OPT --no-headers 2>/dev/null | wc -l)
svc_cnt=$(oc get svc $NS_OPT --no-headers 2>/dev/null | wc -l)
cm_cnt=$(oc get cm $NS_OPT --no-headers 2>/dev/null | wc -l)
secret_cnt=$(oc get secret $NS_OPT --no-headers 2>/dev/null | wc -l)
sa_cnt=$(oc get sa $NS_OPT --no-headers 2>/dev/null | wc -l)

echo "  Pod: ${pod_cnt} | Deployment: ${deploy_cnt} | StatefulSet: ${sts_cnt} | DaemonSet: ${ds_cnt}"
echo "  Service: ${svc_cnt} | ConfigMap: ${cm_cnt} | Secret: ${secret_cnt} | ServiceAccount: ${sa_cnt}"

exit 0
