# [m2d] 질문 이력

oc-mirror --v2 를 이용하여 인터넷망 이미지를 로컬 디스크로 미러링하는 도구 (`m2d.sh`) 관련 질문 이력.

---

=============== [m2d] #001 2026-08-16
[작업자: Kiro]

이번에는 oc-mirror --v2를 이용하여 internet 망의 이미지를 다운 받아서 local disk로 저장하는 프로그램을 shell script로 만들어주고 파일 이름은 m2d.sh 로 작성해줘.

요구사항은 다음과 같아
1. script 작성은 처음 가이드한 것처럼 template.sh 을 참조하는 표준 코딩 가이드를 준수해줘. 사용자 매뉴얼 가이드도 md 파일로 만들어줘. 이하 모두 공통 조건이야.
2. Language : shell script
3. oc-mirror --v2 를 사용하여 인자로 imagesetconfiguration이 정의된 yaml 파일과 disk file 경로를 입력고, cache directory는 내부 변수로 정의해놓는데, /data/ocp-file-mirror/cache 로 초기 설정해 줘.
4. oc-mirror 가 REGISTRY_AUTH_FILE 변수가 설정되어 있으면 오류가 발생하기 때문에 실행시 환경변수를 unset 하여 실행하도록 조치해줘. 해당 명령어 환경에만 반영하면 좋을 것 같아.
5. ocp 4.21 부터 Redhat에서 관리하는 이미지들은 signature 파일을 점검하는 기능으로 보안이 강화되었는데 일부 파트너사들의 이미지들은 signature 파일이 없는 경우가 있어서, signature 파일 download를 skip하는 파라미터를 추가해줘. 기본은 signiture 파일을 포함하여 download 하는 동작이 되어야 해.
6. oc-mirror 프로그램 다운받기 전에 information 을 추가해줘. oc-mirror 버전, 도구이름: m2d.sh, 실행 명령어 전체
7. 만약 m2d.sh 을 인자 없이 실행하면 -h 실행한 것과 동일하게 설명문을 추가하도록 하고, 이때 다음과 같은 예시로 사용자가 변수 입력하는 방법을 쉽게 찾아서 호출 할 수 있도록 해줘. (ex. m2d.sh ./imagesetconfig-release-4.22.10 ./relase-4.22.10 )

[반영 내용]
- oc-mirror v2 mirror-to-disk: oc-mirror --config <yaml> file://<disk> --v2 --cache-dir <cache>
- CACHE_DIR 내부변수 기본값 /data/ocp-file-mirror/cache
- REGISTRY_AUTH_FILE 은 서브셸(env -u 또는 unset)로 해당 명령 실행 환경에서만 unset
- signature: 기본 --remove-signatures=false(포함), --skip-signature 옵션 시 --remove-signatures=true
- 실행 전 Information(oc-mirror 버전/도구이름 m2d.sh/전체 실행문) 출력
- 인자 없이 실행 시 -h 도움말(+예시) 출력

---

=============== [m2d] #002 2026-08-16
[작업자: Kiro]

d2m 은 private registry 인증이 필요해 ${XDG_RUNTIME_DIR}/containers/auth.json 우선이 맞지만, m2d 는 인터넷망 Red Hat/certified vendor registry pull 인증이라 --authfile 로 인증서를 받아 처리하는 것도 가능할 것 같다. 맞으면 m2d 에 --authfile 을 option 으로 추가하고, 있으면 그 방식, 없으면 XDG_RUNTIME_DIR=/run/user/$(id -u) 세팅 + ${XDG_RUNTIME_DIR}/containers/auth.json 참조로 개선. (먼저 추정 확인 후 승인받고 진행)
-> (확인: mirror-to-disk 는 인터넷망 pull 인증 필요, oc-mirror v2 는 --authfile 지원. 추정 타당. 승인됨)

[반영 내용]
- m2d.sh 에 --authfile <path> 옵션 추가. AUTHFILE, XDG_RUNTIME_DIR_FIXED 전역변수 추가.
- build_command: --authfile 지정 시 인자 추가, 미지정 시 미포함.
- run_mirror: --authfile 지정 시 REGISTRY_AUTH_FILE 만 unset, 미지정 시 XDG_RUNTIME_DIR 세팅 추가.
- validate_env: --authfile 지정 시 파일 필수, 미지정 시 XDG auth.json 경고. print_warn 헬퍼 추가.
- print_information/usage/매뉴얼 반영. m2d.sh v1.1, 매뉴얼 v1.1.
