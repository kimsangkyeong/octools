# ocptools.sh 사용자 매뉴얼

| 항목 | 내용 |
|------|------|
| 프로그램 | `ocptools.sh` |
| 문서버전 | v1.4 |
| 작성일 | 2026-09-07 |
| 작성자 | k.s.k & kiro |

---

## 1. 개요

`ocptools.sh`는 OpenShift(OCP) 운영, Podman 프라이빗 레지스트리 관리, 네트워크 진단에 자주 쓰이는 명령어를 메뉴에서 선택하거나 값을 입력하면 실행해 주는 **학습형 통합 CLI 도구**입니다.

이 도구의 핵심은 **실제 실행되는 명령어(실행문)를 화면에 함께 표시**한다는 점입니다. 예를 들어 노드의 multipath 설정을 확인하면 다음과 같이 실행문을 먼저 보여준 뒤 실행합니다.

```
[실행문: oc debug node/worker-1 -q -- chroot /host /bin/bash -c "cat /etc/multipath.conf"]
```

사용자는 반복 사용을 통해 명령어와 파라미터 문법을 자연스럽게 익히고, 나중에 직접 명령을 입력할 때 활용할 수 있습니다.

---

## 2. 사전 요구사항

| 도구 | 용도 | 필수 여부 |
|------|------|-----------|
| `bash` | 스크립트 실행 | 필수 |
| `oc` | OCP 리소스/노드/파일/exec 명령 | OCP 메뉴 사용 시 |
| `podman` | 이미지 pull/tag/push/rmi/login | Podman 메뉴 사용 시 |
| `curl` | 레지스트리 API, 네트워크 호출 | 레지스트리/네트워크 메뉴 사용 시 |
| `skopeo` | 이미지 inspect (있으면 우선 사용) | 선택 |
| `jq` | JSON 보기 좋게 출력 | 선택 |
| `ncat`/`nc` | 포트/패킷 확인 | 네트워크 메뉴 사용 시 |
| `chronyc` | 시간 동기화 확인 | 시스템 메뉴 사용 시 |
| `ip`/`nmcli` | NIC 정보/제어 | 시스템 메뉴 사용 시 |

> 시작 시 `oc`, `podman`, `curl` 설치 여부를 점검하여 안내합니다. (없어도 실행은 가능하며, 해당 메뉴 사용 시 설치가 필요합니다.)

---

## 3. 설치 및 실행

```bash
# 실행 권한 부여
chmod +x ocptools.sh

# 실행
./ocptools.sh
```

- OCP 관련 메뉴는 실행 시 **oc 로그인 여부를 자동 확인**합니다. 미로그인 상태면 로그인 방법을 안내하고, 원시 에러 메시지가 노출되지 않도록 처리합니다.
- 프로그램은 성능용 임시 폴더 `$PWD/.ocptools`를 생성하며, **종료 시 자동 삭제**하여 흔적을 남기지 않습니다.
- `Ctrl+C`(SIGINT) 등 시그널 발생 시 로그가 `$HOME/tmp/ocptools.sh.log`에 기록됩니다.

---

## 4. 화면 조작법

메뉴는 항목이 많을 경우 **화면을 2열로 이분할**하고 **페이지**로 나누어 표시합니다.

| 입력 | 동작 |
|------|------|
| 숫자 + Enter | 해당 번호 항목 선택 |
| `n` | 다음 페이지 |
| `p` | 이전 페이지 |
| `b` | 뒤로 가기 (상위 메뉴로) |
| `q` | 프로그램 종료 |

리소스(node/pod/namespace/NIC)가 필요한 경우, 아래 두 방식 중 선택할 수 있습니다.

- **목록에서 선택**: `oc`/`ip` 명령으로 실제 목록을 조회해 메뉴로 제공
- **직접 입력**: 이미 이름을 알고 있으면 빠르게 입력 (편의성)

---

## 5. 메뉴 구성

명령어는 **유형(Category) → 세부 명령어** 2단계로 구성됩니다.

### 5.1 OCP 리소스 조회 (`oc get`)

| 세부 명령 | 실행문 예시 |
|-----------|-------------|
| ClusterOperator | `oc get co -o wide` |
| MachineConfig / MCP | `oc get mc` / `oc get mcp` |
| CatalogSource | `oc get catalogsource -n <ns>` |
| IDMS / ITMS | `oc get idms` / `oc get itms` |
| Node | `oc get node -o wide` |
| Pod / Service / PVC / CM / Secret | `oc get <res> -n <ns>` |
| SCC / PV / CSR | `oc get scc` / `oc get pv` / `oc get csr` |
| PDB / Job / StatefulSet | `oc get <res> -n <ns>` |
| ClusterVersion | `oc get clusterversion` |
| Operator(CSV) / InstallPlan | `oc get csv -n <ns>` / `oc get installplan -n <ns>` |
| Event(시간순) | `oc get events -n <ns> --sort-by='.lastTimestamp'` |
| 임의 리소스 직접 조회 | `oc get <입력> [ -n <ns> ] [옵션]` |

### 5.2 OCP 노드 접속 실행 (`oc debug node`)

노드를 선택한 뒤 `chroot /host` 환경에서 명령을 실행합니다.

| 세부 명령 | 실행문 예시 |
|-----------|-------------|
| multipath 설정 | `oc debug node/<node> -q -- chroot /host /bin/bash -c "cat /etc/multipath.conf"` |
| 마운트/블록 디바이스 | `... "mount"` / `... "lsblk"` |
| chrony/NIC/route | `... "chronyc sources -v"` / `"ip -br addr"` / `"ip route"` |
| kubelet 로그 | `... "journalctl -u kubelet --no-pager -n 100"` |
| 노드 명령 직접 입력 | 임의 명령을 노드에서 실행 |

### 5.3 OCP 파일 송수신 (`oc cp` / `oc rsync`)

| 세부 명령 | 실행문 예시 |
|-----------|-------------|
| 다운로드 | `oc cp <ns>/<pod>:<path> <local>` |
| 업로드 | `oc cp <local> <ns>/<pod>:<path>` |
| 디렉토리 동기화 | `oc rsync <src> <ns>/<pod>:<dst>` (방향 선택) |

### 5.4 OCP Pod 실행/진입 (`oc exec` / `rsh` / `logs`)

| 세부 명령 | 실행문 예시 |
|-----------|-------------|
| 명령 실행 | `oc exec -n <ns> pod/<pod> -- /bin/sh -c "<cmd>"` |
| 셸 접속 | `oc rsh -n <ns> pod/<pod>` |
| 로그 | `oc logs -n <ns> pod/<pod> --tail=<n>` |

### 5.5 Podman 레지스트리

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| 로그인 | `podman login <registry> -u <user>` | |
| 카탈로그 조회 | `curl -sk https://<reg>/v2/_catalog?n=1000` | 조회방식 3가지(전체/개수/기본), 전체는 Link 헤더 페이지네이션으로 모두 수집 |
| 태그 목록 | `curl -sk https://<reg>/v2/<repo>/tags/list` | jq 있으면 정렬 출력 |
| 이미지 상세 | `skopeo inspect docker://<image>` 또는 `podman inspect <image>` | |
| pull | `podman pull --tls-verify=false <image>` | |
| 태그 추가/복사 | `podman tag <src> <dst>` | |
| push | `podman push --tls-verify=false <image>` | |
| 이미지 삭제 | `podman rmi <image>` | 실행 전 확인 |
| 레지스트리 태그 삭제 | digest 조회 후 `curl -X DELETE .../manifests/<digest>` | 실행 전 확인 |

> **레지스트리 주소 기본값**: 로그인 / 카탈로그 조회 / 태그 목록 / 레지스트리 태그 삭제 메뉴에서 레지스트리 주소를 입력받을 때, 내부 변수 `DEFAULT_REGISTRY`(기본값 `ocprgst.bss.skt:5000`)를 참고정보로 함께 보여줍니다. 프롬프트에서 아무 것도 입력하지 않고 **엔터만 누르면 이 기본값으로 처리**되며, 다른 값을 입력하면 입력값이 사용됩니다. 기본 레지스트리를 바꾸려면 스크립트 상단의 `DEFAULT_REGISTRY` 변수만 수정하면 됩니다.

> **카탈로그 전체 목록 조회**: `_catalog` API는 레지스트리 설정에 따라 결과가 페이지로 나뉘어 일부만 반환될 수 있습니다. 카탈로그 조회 시 다음 방식 중 선택합니다.
> - **[1] 전체 목록(권장)**: `?n=1000`으로 조회한 뒤 응답의 `Link` 헤더가 있으면 `?last=<마지막repo>`로 다음 페이지를 반복 조회하여 전체를 합칩니다. (jq 필요)
> - **[2] 개수 지정**: `?n=<입력값>`으로 지정한 개수만 조회
> - **[3] 기본 조회**: 옵션 없이 레지스트리 기본 동작으로 조회

### 5.6 네트워크 진단

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| curl 호출 | `curl -sk -o /dev/null -w 'HTTP:%{http_code} ...' <url>` | |
| curl --resolve | `curl -sk -v --resolve <host>:<port>:<ip>[,<ip2>] <url>` | 이름→IP 치환. 멀티 IP는 콤마 구분. 커스텀 포트는 `<port>`와 URL 포트를 동일하게 |
| curl --connect-to | `curl -sk -v --connect-to <host1>:<port1>:<host2>:<port2> <url>` | 도메인 유지 + 다른 host/port로 우회 접속(예: 8081). `host:port:ip:port` 시나리오에 사용 |
| ncat 포트 확인 | `ncat -z -v -w 3 <host> <port>` | |
| ping | `ping -c <n> <host>` | |
| 소켓 상태 | `ss -tlnp` (없으면 `netstat -tlnp`) | |
| tcpdump 패킷 캡처 | `sudo tcpdump -i <iface> -nn -vv -c <n> 'host <ip> and port <port>'` | 실행 전 확인. `-w`로 pcap 저장 가능 |

### 5.7 시스템 / 네트워크

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| chrony 소스 | `chronyc sources -v` | |
| chrony 상태 | `chronyc tracking` | |
| NIC 정보 | `ip -br addr; nmcli device status` | |
| NIC UP | `sudo ip link set <nic> up` | 실행 전 확인 |
| NIC DOWN | `sudo ip link set <nic> down` | 실행 전 확인(세션 끊김 주의) |
| 라우팅 | `ip route` | |

### 5.8 OCP 인증서 조회

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| 전체 TLS Secret 만료일 | `oc get secrets -A ... tls.crt ... \| base64 -d \| openssl x509 -noout -enddate` | openssl 필요 |
| 특정 Secret 상세/만료 | `oc get secret <name> -n <ns> -o jsonpath='{.data.tls\.crt}' \| base64 -d \| openssl x509 -noout -enddate` | 키/전체상세 선택 |
| Node kubelet 인증서 | `oc debug node/<node> -- chroot /host ... openssl x509 -in kubelet-*-current.pem -noout -enddate` | |
| API endpoint 인증서 | `echo \| openssl s_client -connect <host:port> -servername <host> \| openssl x509 -noout -dates` | |

> 인증서 조회 방식은 Red Hat 지식베이스(Solution 3930291, 7028654)를 참고하여 재구성했습니다.

### 5.9 OCP 관리 작업 (`oc adm` / `oc patch`)

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| 리소스 patch | `oc patch <종류> <이름> [-n <ns>] --type=<merge/json/strategic> -p '<patch>'` | 실행 전 확인 |
| 노드 cordon/uncordon | `oc adm cordon <node>` / `oc adm uncordon <node>` | 실행 전 확인 |
| 노드 drain | `oc adm drain <node> --ignore-daemonsets --delete-emptydir-data --force` | 실행 전 확인(Pod 축출) |
| top node / top pod | `oc adm top node` / `oc adm top pod -n <ns>` | |

### 5.10 노드 tcpdump / ss (`oc debug node`)

5.2 노드 접속 실행에 다음이 추가되었습니다.

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| 노드 소켓/포트 상태(ss) | `oc debug node/<node> -- chroot /host ... ss -tulnp` | |
| 노드 tcpdump | `oc debug node/<node> -- chroot /host ... tcpdump -i <iface> -nn -c <n> '<filter>'` | 실행 전 확인 |

### 5.11 테스트 이미지 (busybox / nginx / toolbox)

임시 테스트 Pod(라벨 `app=ocptools-test`)로 네트워크/DNS/HTTP를 검증합니다.

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| busybox 테스트 | `oc run ocptools-busybox --image=busybox --rm -it -- sh -c 'nslookup <target>; wget -qO- http://<target>'` | 일회성(--rm) |
| nginx 테스트 | `oc run ocptools-nginx --image=nginx --port=80` 후 `oc exec ... curl localhost` | 정리 필요 |
| toolbox(노드) | `oc debug node/<node> -- chroot /host toolbox <cmd>` | RHCOS 진단 |
| 테스트 리소스 정리 | `oc delete pod -l app=ocptools-test -n <ns>` | 실행 전 확인 |

### 5.12 Istio 서비스메시 (`istioctl`)

| 세부 명령 | 실행문 예시 | 비고 |
|-----------|-------------|------|
| version | `istioctl version` | istioctl/컨트롤플레인 버전 |
| proxy-status | `istioctl proxy-status` | sidecar 동기화 상태 |
| proxy-config | `istioctl proxy-config <all/cluster/listener/route/...> <pod>.<ns>` | Envoy 설정 조회 |
| analyze | `istioctl analyze [-n <ns> \| --all-namespaces]` | 구성 문제 진단 |
| 직접 입력 | `istioctl <입력>` | 임의 하위 명령 |

### 5.13 유틸리티 (crt merge / json merge / openssl)

**복수 crt → ConfigMap** (CA bundle 생성/갱신)

| 방식 | 실행문 예시 |
|------|-------------|
| 신규 생성 | `oc create configmap <name> -n <ns> --from-file=<key>=<merged.pem>` |
| 갱신(apply) | `oc create configmap <name> ... --dry-run=client -o yaml \| oc apply -f -` |

- 입력한 여러 crt 파일을 하나로 병합한 뒤 지정 key(예: `ca-bundle.crt`)로 ConfigMap을 만들거나 갱신합니다. (실행 전 확인)

**복수 JSON → merged JSON** (jq)

| 방식 | 실행문 예시 |
|------|-------------|
| 객체 깊은 병합(뒤 파일 우선) | `jq -s 'reduce .[] as $x ({}; . * $x)' a.json b.json > merged.json` |
| 배열로 결합 | `jq -s '.' a.json b.json > merged.json` |
| 얕은 병합 | `jq -s 'reduce .[] as $x ({}; . + $x)' a.json b.json > merged.json` |

**openssl 사용법** (메뉴에서 선택 후 실행)

| 항목 | 실행문 예시 |
|------|-------------|
| 인증서 상세 | `openssl x509 -in <crt> -text -noout` |
| 만료일 | `openssl x509 -in <crt> -noout -enddate` |
| subject/issuer | `openssl x509 -in <crt> -noout -subject -issuer` |
| 원격 서버 인증서 | `echo \| openssl s_client -connect <host:port> -servername <host> \| openssl x509 -noout -dates` |
| CSR 생성 | `openssl req -new -newkey rsa:2048 -nodes -keyout <key> -out <csr>` |
| 자체서명 인증서 | `openssl req -x509 -newkey rsa:2048 -nodes -keyout <key> -out <crt> -days <n>` |
| PFX→PEM | `openssl pkcs12 -in <pfx> -out <pem> -nodes` |
| 지문(SHA256) | `openssl x509 -in <crt> -noout -fingerprint -sha256` |
| key/crt 짝 확인 | `openssl x509 -noout -modulus -in <crt> \| openssl md5` 와 `openssl rsa -noout -modulus -in <key> \| openssl md5` 비교 |

---

## 6. 안전장치 (되돌리기 어려운 명령)

다음 명령은 실행 전 **`y/N` 확인**을 거칩니다. 실행문을 먼저 보여준 뒤 사용자가 `y`를 입력해야 실행됩니다.

- 이미지 삭제: `podman rmi`
- 레지스트리 태그 삭제: `DELETE .../manifests/<digest>`
- NIC 활성화/비활성화: `ip link set <nic> up|down`
- tcpdump 패킷 캡처: `sudo tcpdump ...` / 노드 tcpdump (루트 권한, 장시간 캡처 가능)
- 리소스 patch: `oc patch ...`
- 노드 cordon/uncordon/drain: `oc adm cordon|uncordon|drain <node>`
- 테스트 리소스 정리: `oc delete pod -l app=ocptools-test`
- CA bundle ConfigMap 생성/갱신: `oc create configmap ...` / `oc apply -f -`

> **--resolve vs --connect-to 정리**
> - `--resolve <HOST>:<PORT>:<ADDRESS>`: DNS 이름 해석만 바꿉니다. HOST를 지정 IP로 해석하되 접속 포트는 URL의 포트를 그대로 사용합니다. 커스텀 포트(예: 8081)로 접속하려면 `<PORT>`와 URL 포트를 모두 8081로 맞춰야 합니다. 여러 IP는 콤마로 나열할 수 있습니다.
> - `--connect-to <HOST1>:<PORT1>:<HOST2>:<PORT2>`: 접속 대상 host/port 자체를 다른 host/port로 바꿉니다. 도메인(TLS SNI/Host 헤더)은 유지하면서 다른 IP나 다른 포트로 우회 접속할 때 사용합니다. `host:port:ip:port` 형태가 필요한 경우 이 옵션이 정확합니다.
> (출처 재구성: curl 공식 매뉴얼 CURLOPT_RESOLVE / 내용은 라이선스 준수를 위해 재작성)

---

## 7. 확장 방법 (명령어/유형 추가)

이 도구는 **배열 기반 메타데이터**로 관리되어 쉽게 확장할 수 있습니다. `array depth`는 사람이 분석하기 쉽도록 **최대 2**로 유지합니다.

### 7.1 세부 명령 추가

`register_all_commands()` 함수에 `register_cmd` 한 줄과 핸들러 함수 하나만 추가하면 메뉴에 자동 반영됩니다.

```bash
# register_cmd <유형ID> <명령ID> <라벨> <핸들러(함수명+인자)> <confirm(Y/N)> <설명>
register_cmd ocp_get g_ingress "Ingress 조회" "h_ocget_ns ingress" N "인그레스 목록"
```

- `handler` 필드는 **함수명 문자열**로, 내부적으로 `eval` 호출됩니다(함수 포인터 방식).
- namespace가 필요하면 기존 `h_ocget_ns <리소스>` 핸들러를 재사용할 수 있습니다.

### 7.2 새 유형(카테고리) 추가

```bash
# 1) CAT_IDS 배열에 유형 ID 추가
CAT_IDS=( ... "my_cat" )

# 2) CAT_LABEL 에 표시명 추가
CAT_LABEL[my_cat]="내 커스텀 명령 그룹"

# 3) register_all_commands 에 해당 유형의 명령들 등록
register_cmd my_cat mc_hello "인사 출력" "h_hello" N "테스트 명령"
```

### 7.3 커스텀 핸들러 작성 규약

```bash
h_hello()
{
  # 1) 필요 시 로그인/도구 확인
  #    check_oc_login || { pause_enter; return 1; }

  # 2) 인자 입력 (기본값 지원)
  local target
  ask_input "대상 입력" target "world"

  # 3) run_cmd 로 실행문 표시 + 실행 (위험 명령은 두번째 인자 "Y")
  run_cmd "echo hello ${target}"

  # 4) 결과 확인 대기
  pause_enter
}
```

---

## 8. 화면 출력(색상) 처리

색상 코드 정의(`C_RED`, `C_GREEN`, `C_YELLOW`, `C_BLUE`, `C_CYAN`, `C_WHITE`, `C_BOLD`)는 유지하되, 일부 터미널에서 글씨가 안 보이는 문제를 피하기 위해 **화면 출력은 모두 `C_BOLD`(굵게)로 통일** 되어 있습니다.

- 대상: 타이틀 배너, 실행문 표시, 메뉴/프롬프트, 경고/오류 메시지 등 모든 출력.
- 나중에 특정 메시지를 색상으로 표시하고 싶으면, 해당 `printf` 의 `${C_BOLD}` 를 원하는 색상 변수(예: `${C_GREEN}`)로 수동 변경하면 됩니다.

---

## 9. 로그 및 임시 파일

| 항목 | 경로 | 설명 |
|------|------|------|
| 시그널 로그 | `$HOME/tmp/ocptools.sh.log` | SIGINT/SIGQUIT/SIGTERM 발생 기록 |
| 성능용 메타 | `$PWD/.ocptools/` | 실행 중 생성, **종료 시 자동 삭제** |

---

## 10. 문제 해결 (Troubleshooting)

| 증상 | 원인 | 해결 |
|------|------|------|
| "oc 로그인이 되어 있지 않습니다" | 세션 만료/미로그인 | 안내된 `oc login` 실행 |
| "[oc] 명령을 찾을 수 없습니다" | oc 미설치/PATH 누락 | oc 설치 및 PATH 등록 |
| 레지스트리 태그 삭제 실패 | 레지스트리 삭제 미허용 | 레지스트리 `storage.delete.enabled=true` 확인 |
| NIC DOWN 후 접속 끊김 | 원격 세션 인터페이스 비활성화 | 콘솔 접속으로 복구 (신중히 사용) |
| 한글/정렬 깨짐 | 터미널 폭 좁음 | 터미널 창을 넓히거나 페이지 이동(`n`/`p`) 사용 |

---

## 변경이력

| 버전 | 날짜 | 변경내용 | 작성자 |
|------|------|----------|--------|
| v1.0 | 2026-08-16 | 최초 작성 | k.s.k & kiro |
| v1.1 | 2026-08-16 | 카탈로그 전체목록 조회, tcpdump 추가, curl --resolve 보완 및 --connect-to 추가 | k.s.k & kiro |
| v1.2 | 2026-09-07 | 레지스트리 주소 입력 시 기본 참고정보(DEFAULT_REGISTRY=ocprgst.bss.skt:5000) 제시 및 엔터 시 기본값 처리, 화면 출력 C_BOLD 통일(색상 정의는 유지) | k.s.k & kiro |
| v1.3 | 2026-09-07 | 인증서 유효일자 조회(ocp_cert), Pod 이미지 정보 조회, OCP 관리작업(oc adm/patch: ocp_adm), 노드 tcpdump/ss, 테스트 이미지(busybox/toolbox/nginx: test_img) 추가 | k.s.k & kiro |
| v1.4 | 2026-09-07 | istioctl(istio), 유틸리티(util) 추가: 복수 crt merge→ConfigMap 생성/patch, 복수 JSON merge(jq), openssl 사용법 | k.s.k & kiro |
