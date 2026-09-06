# [d2m] 질문 이력

oc-mirror --v2 로 디스크 파일을 private registry로 미러링하는 도구 (`d2m.sh`) 관련 질문 이력.

---

=============== [d2m] #001 2026-08-16
[작업자: Kiro]

이번에는 m2d에서 다운받아 놓은 disk file을 이용하여 private registry로 저장하는 프로그램을 만들어줘.

요구사항은 다음과 같아
1. script 작성은 처음 가이드한 것처럼 template.sh 을 참조하는 표준 코딩 가이드를 준수해줘. 사용자 매뉴얼 가이드도 md 파일로 만들어줘. 이하 모두 공통 조건이야.
2. Language : shell script
3. oc-mirror --v2 를 사용하여 인자로 imagesetconfiguration이 정의된 yaml 파일과 disk file 경로를 입력받고, cache directory는 내부 변수로 정의해 놓고, /data/ocp-file-mirror/cache 로 초기 설정. private registry 저장소(ocp4/relese, ocp4/operator, ocp4/infra, ocp5/relese, ocp5/operator, ocp5/infra)를 목록 선택 또는 입력으로 지정. private registry 주소는 https://ocprgst.bss.skt:5000. auth file 은 옵션(기본 내부변수 /data/pullsecret/merged-pullsecrete.json), XDG_RUNTIME_DIR 유실로 인한 인증오류 회피를 위해 --authfile 명시.
4. private registry 저장소는 내부 변수 목록으로 관리(확장 유연). 관리되지 않는 경로면 오류처리 + 선택 가능 목록 출력.
5. d2m 도 cache directory 사용 (확인 결과: disk-to-mirror 도 --cache-dir 사용하므로 반영).
6. d2m 실행 시 information 추가: oc-mirror 버전, 도구이름, 실행 명령어 전체.
7. 인자 없이 실행하면 -h 와 동일하게 설명문 출력.

[반영 내용]
- disk-to-mirror: oc-mirror --config <yaml> --from file://<disk> docker://<REGISTRY>/<repo> --v2 --cache-dir <cache> --authfile <authfile>
- REGISTRY_HOST=ocprgst.bss.skt:5000, REPO_LIST=(ocp4/release ocp4/operator ocp4/infra ocp5/release ocp5/operator ocp5/infra) (relese 오타 -> release 수정)
- 저장소: 목록 선택 or 인자 입력(목록 외 값이면 오류 + 목록 안내)
- AUTHFILE 기본 /data/pullsecret/merged-pullsecrete.json, --authfile 옵션 override
- REGISTRY_AUTH_FILE unset(실행환경만) + --authfile 명시로 XDG_RUNTIME_DIR 유실 회피
- 실행 전 Information, 인자 없으면 -h 출력

---

=============== [d2m] #002 2026-08-16
[작업자: Kiro]

오타가 맞네. release 로 수정해줘.

[반영 내용]
- REPO_LIST 의 ocp4/relese, ocp5/relese -> ocp4/release, ocp5/release 로 수정.
- d2m.sh 주석/usage 예시, docs/d2m_manual.md 저장소 목록/예시 모두 release 로 정정.
- d2m.sh v1.1 반영.

---

=============== [d2m] #003 2026-08-16
[작업자: Kiro]

d2m.sh 에 --skip-signature 옵션이 있던데, 필요한 것인가? m2d에서만 필요한 변수같은데 확인해줘.
-> (검토 결과: d2m 요구사항에 signature 언급 없었고, 서명 유무는 다운로드(m2d) 단계에서 결정됨. d2m 은 디스크->registry 전송이라 skip 옵션 실익 없음. 제거가 맞음)

[반영 내용]
- d2m.sh 에서 SKIP_SIGNATURE 변수, --skip-signature 파싱, --remove-signatures 플래그, Information signature 라인, usage 옵션/예시 모두 제거.
- docs/d2m_manual.md 의 관련 옵션/예시/문제해결 정정(서명 처리는 m2d 에서 결정한다고 안내).
- d2m.sh v1.2, 매뉴얼 v1.2.

---

=============== [d2m] #004 2026-08-16
[작업자: Kiro]

authfile 에 /data/pullsecret/merged-pullsecrete.json 을 변수로 처리했지만 권한 문제로 ${XDG_RUNTIME_DIR}/containers/auth.json 에 복사 후 처리했었음. oc-mirror --v2 는 내부 로직상 authfile 인자를 줘도 ${XDG_RUNTIME_DIR}/containers/auth.json 을 찾으므로, 차라리 실행 user 기준으로 XDG_RUNTIME_DIR 을 세팅해 전달하는 방식이 더 완벽할 것 같다. (XDG_RUNTIME_DIR 정상 세팅 상태면 해당 auth.json 에 인증 token 이 있음)
-> (확인: oc-mirror/podman v2 는 ${XDG_RUNTIME_DIR}/containers/auth.json 을 기본 참조. XDG_RUNTIME_DIR 표준값 /run/user/<uid>. 세팅 방식이 근본 해결 맞음)

[반영 내용]
- AUTHFILE 기본값을 빈 값으로 변경. --authfile 은 선택 옵션으로만 유지(지정 시에만 인자 추가).
- XDG_RUNTIME_DIR_FIXED="/run/user/$(id -u)" 도입.
- run_mirror: env -u REGISTRY_AUTH_FILE XDG_RUNTIME_DIR=<fixed> bash -c "..." 로 실행 환경에만 세팅.
- validate_env: --authfile 지정 시 파일 필수, 미지정 시 XDG 경로 auth.json 존재를 경고 수준으로 점검.
- build_command: --authfile 은 지정된 경우에만 추가. print_information/usage/매뉴얼 갱신.
- d2m.sh v1.3, 매뉴얼 v1.3.

---

=============== [d2m] #005 2026-08-16
[작업자: Kiro]

--authfile 옵션은 제거해줘. 그리고 "${XDG_RUNTIME_DIR_FIXED}/containers/auth.json" 파일이 없는 경우 안내 메시지를 수정.
(before) 먼저 'podman login ${REGISTRY_HOST}' 로 로그인하거나, --authfile 로 경로를 지정하세요.
(after)  먼저 'podman login ${REGISTRY_HOST}' 로 로그인하거나, 인증서파일을 "${XDG_RUNTIME_DIR_FIXED}/containers/auth.json" 로 복사하세요.

[반영 내용]
- d2m.sh 에서 AUTHFILE 변수, --authfile 파싱, usage 옵션/예시, build_command 조건부 인자, print_information 분기 모두 제거.
- validate_env 인증 점검을 XDG 경로 단일 체크로 단순화하고 안내 메시지를 요청대로 수정.
- docs/d2m_manual.md 의 --authfile 관련 항목 전부 정리(옵션표/내부설정표/예시/인증섹션/문제해결).
- d2m.sh v1.4, 매뉴얼 v1.4.
