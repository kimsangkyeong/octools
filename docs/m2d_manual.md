# m2d.sh 사용자 매뉴얼

| 항목 | 내용 |
|------|------|
| 프로그램 | `m2d.sh` |
| 식별자 | `[m2d]` |
| 문서버전 | v1.1 |
| 작성일 | 2026-08-16 |
| 작성자 | k.s.k & kiro |

---

## 1. 개요

`m2d.sh`(mirror to disk)는 `oc-mirror` 플러그인 **v2(`--v2`)** 를 사용하여 인터넷망의 OCP 릴리스/Operator/추가 이미지를 **로컬 디스크로 다운로드(mirror-to-disk)** 하는 래퍼 스크립트입니다.

- ImageSetConfiguration YAML과 디스크 저장 경로를 인자로 받아 실행합니다.
- 실행 전 `oc-mirror` 버전, 도구 이름, 전체 실행 명령어를 **Information**으로 보여줍니다.
- 서명(signature) 다운로드 포함/skip을 옵션으로 선택할 수 있습니다.

---

## 2. 사전 요구사항

| 항목 | 설명 |
|------|------|
| `oc-mirror` (v2 지원) | 필수. 인터넷 연결 시스템에 설치 |
| Red Hat registry 인증 | pull secret 등 `oc-mirror`가 요구하는 인증 구성 |
| 인터넷 연결 | Red Hat 공식 레지스트리에서 이미지를 내려받기 위해 필요 |
| 디스크 여유 공간 | 미러링 이미지 크기에 충분한 공간 |

---

## 3. 설치 및 실행

```bash
chmod +x m2d.sh
./m2d.sh <imagesetconfig_yaml> <disk_path> [옵션]
```

**인자 없이 실행하면** `-h`와 동일하게 사용법이 출력됩니다.

```bash
./m2d.sh
```

---

## 4. 인자 및 옵션

| 구분 | 이름 | 설명 |
|------|------|------|
| 인자1 | `imagesetconfig_yaml` | ImageSetConfiguration이 정의된 YAML 경로 (필수) |
| 인자2 | `disk_path` | 이미지를 저장할 로컬 디스크 경로 (필수, `file://` 자동 부여) |
| 옵션 | `--authfile <path>` | (선택) 인터넷망 pull secret 인증 파일 경로. 미지정 시 `${XDG_RUNTIME_DIR}/containers/auth.json` 사용 |
| 옵션 | `--skip-signature` | 서명 파일 다운로드를 건너뜀 (`--remove-signatures=true`) |
| 옵션 | `-h`, `--help` | 도움말 출력 |

### 내부 설정 (스크립트 변수)

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `CACHE_DIR` | `/data/ocp-file-mirror/cache` | `oc-mirror --cache-dir`로 전달. 스크립트 내부에서 변경 가능 |
| `XDG_RUNTIME_DIR_FIXED` | `/run/user/$(id -u)` | `--authfile` 미지정 시 실행 환경에 세팅되어 `containers/auth.json` 참조 |

---

## 5. 사용 예시

```bash
# 기본 실행 (인증: ${XDG_RUNTIME_DIR}/containers/auth.json)
./m2d.sh ./imagesetconfig-release-4.22.10 ./relase-4.22.10

# pull secret 파일을 직접 지정
./m2d.sh ./imagesetconfig-release-4.22.10 ./relase-4.22.10 --authfile /data/pullsecret/pull-secret.json

# 서명 다운로드 skip (서명 없는 파트너 이미지 포함 시)
./m2d.sh ./imagesetconfig-release-4.22.10 ./relase-4.22.10 --skip-signature
```

실제 실행되는 명령(예):

```bash
oc-mirror --config ./imagesetconfig-release-4.22.10 file://./relase-4.22.10 \
          --v2 --cache-dir /data/ocp-file-mirror/cache --remove-signatures=false
```

---

## 6. 서명(signature) 처리

| 모드 | oc-mirror 플래그 | 설명 |
|------|------------------|------|
| 기본(포함) | `--remove-signatures=false` | 이미지 서명을 함께 다운로드 |
| skip | `--remove-signatures=true` | 서명 다운로드를 건너뜀 |

- OCP 4.21+ 부터 Red Hat 관리 이미지는 서명 미러링이 기본 동작으로 강화되었습니다.
- 일부 파트너사 이미지는 서명 파일이 없어 미러링이 실패할 수 있습니다. 이 경우 `--skip-signature`로 서명 다운로드를 건너뛰면 됩니다.
- **기본 동작은 서명 포함**입니다. 필요할 때만 skip을 사용하세요.

> 참고: 서명 처리 플래그 동작은 [Red Hat oc-mirror v2 서명 미러링 문서](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/disconnected_environments/about-installing-oc-mirror-v2)를 참고했습니다. (내용은 라이선스 준수를 위해 재구성)

---

## 7. 인증 및 환경변수 처리

m2d는 인터넷망의 Red Hat/vendor registry에서 이미지를 내려받으므로 pull secret 인증이 필요합니다. 인증 방식은 두 가지를 지원합니다.

1. **`--authfile <path>` 지정 시**: 해당 pull secret 파일로 인증합니다. (`oc-mirror ... --authfile <path>`) pull secret 파일을 별도 경로에서 관리하는 경우 편리합니다.
2. **`--authfile` 미지정 시**: 실행 환경에 `XDG_RUNTIME_DIR=/run/user/$(id -u)`를 세팅하고 `${XDG_RUNTIME_DIR}/containers/auth.json`을 참조합니다. (`podman login`으로 생성된 인증 사용)

추가로 두 경우 모두 **`REGISTRY_AUTH_FILE`을 해당 실행 환경에서만 unset** 합니다. (이 변수가 설정되어 있으면 oc-mirror가 오류를 낼 수 있음. 현재/부모 셸 환경은 변경되지 않음)

> pull secret은 https://console.redhat.com/openshift/install/pull-secret 에서 받아 `auth.json`에 병합할 수 있습니다.

---

## 8. 실행 전 Information 출력

`oc-mirror` 실행(다운로드) 직전에 다음 정보가 출력됩니다.

```
==================== [Information] ====================
  도구 이름        : m2d.sh
  oc-mirror 버전   : (oc-mirror version 결과)
  config(yaml)     : ./imagesetconfig-release-4.22.10
  disk 경로        : ./relase-4.22.10
  cache 경로       : /data/ocp-file-mirror/cache
  XDG_RUNTIME_DIR  : /run/user/1000 (실행 환경에 세팅)   # --authfile 미지정 시
  인증(auth.json)  : /run/user/1000/containers/auth.json # --authfile 미지정 시
  signature        : 포함 (--remove-signatures=false, 기본)
  REGISTRY_AUTH_FILE : 이 명령 실행 환경에서 unset 처리
  실행 명령어      :
    oc-mirror --config ./imagesetconfig-release-4.22.10 file://./relase-4.22.10 --v2 --cache-dir /data/ocp-file-mirror/cache --remove-signatures=false
======================================================
```

> `--authfile`을 지정하면 위 XDG_RUNTIME_DIR/인증 라인 대신 `인증(authfile) : <경로> (명시 지정)`이 표시되고, 실행 명령어에 `--authfile <경로>`가 포함됩니다.

---

## 9. 종료 코드

| 코드 | 의미 |
|------|------|
| 0 | 미러링 성공 |
| 1 | 인자 오류 / 사전 점검 실패 |
| 그 외 | `oc-mirror` 실행 실패 (oc-mirror 반환 코드 전달) |

---

## 10. 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| `oc-mirror 명령을 찾을 수 없습니다` | 미설치/PATH 누락 | oc-mirror v2 설치 및 PATH 등록 |
| 서명 관련 미러링 실패 | 파트너 이미지 서명 없음 | `--skip-signature` 사용 |
| 인증 오류 | pull secret 미설정 | `--authfile`로 pull secret 지정, 또는 `podman login` 후 `${XDG_RUNTIME_DIR}/containers/auth.json` 사용 |
| `지정한 인증 파일(--authfile)이 없습니다` | authfile 경로 오류 | 올바른 pull secret 경로 지정 |
| 캐시/디스크 쓰기 실패 | 권한/공간 부족 | 경로 권한과 여유 공간 확인 |

---

## 변경이력

| 버전 | 날짜 | 변경내용 | 작성자 |
|------|------|----------|--------|
| v1.0 | 2026-08-16 | 최초 작성 | k.s.k & kiro |
| v1.1 | 2026-08-16 | --authfile 옵션 추가(인터넷망 pull secret 지정). 미지정 시 XDG_RUNTIME_DIR 세팅 + auth.json 참조 | k.s.k & kiro |
