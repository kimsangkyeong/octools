# d2m.sh 사용자 매뉴얼

| 항목 | 내용 |
|------|------|
| 프로그램 | `d2m.sh` |
| 식별자 | `[d2m]` |
| 문서버전 | v1.5 |
| 작성일 | 2026-09-07 |
| 작성자 | k.s.k & kiro |

---

## 1. 개요

`d2m.sh`(disk to mirror)는 `oc-mirror` 플러그인 **v2(`--v2`)** 를 사용하여 `m2d.sh`로 내려받아 둔 **디스크 파일을 private registry로 전송(disk-to-mirror)** 하는 래퍼 스크립트입니다.

- ImageSetConfiguration YAML, 디스크 경로, 대상 저장소(repository)를 지정하여 실행합니다.
- 저장소는 내부 관리 목록에서 선택하거나 인자로 직접 지정할 수 있습니다.
- 실행 전 `oc-mirror` 버전, 도구 이름, 전체 실행 명령어를 **Information**으로 보여줍니다.

---

## 2. 사전 요구사항

| 항목 | 설명 |
|------|------|
| `oc-mirror` (v2 지원) | 필수 |
| 디스크 파일 | `m2d.sh`로 미러링해 둔 디스크 경로 |
| 인증 파일 | private registry pull/push 인증. `${XDG_RUNTIME_DIR}/containers/auth.json` |
| private registry 접근 | `ocprgst.bss.skt:5000` 로 push 가능해야 함 |

---

## 3. 설치 및 실행

```bash
chmod +x d2m.sh
./d2m.sh <imagesetconfig_yaml> <disk_path> [repo] [옵션]
```

**인자 없이 실행하면** `-h`와 동일하게 사용법이 출력됩니다.

```bash
./d2m.sh
```

---

## 4. 인자 및 옵션

| 구분 | 이름 | 설명 |
|------|------|------|
| 인자1 | `imagesetconfig_yaml` | ImageSetConfiguration YAML 경로 (필수) |
| 인자2 | `disk_path` | m2d로 내려받은 디스크 경로 (필수, `file://` 자동 부여) |
| 인자3 | `repo` | 대상 저장소 (선택). 생략 시 목록에서 번호로 선택 |
| 옵션 | `-h`, `--help` | 도움말 출력 |

### 내부 설정 (스크립트 변수)

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `REGISTRY_HOST` | `ocprgst.bss.skt:5000` | private registry 주소 |
| `CACHE_DIR` | `/data/ocp-file-mirror/cache` | oc-mirror 캐시 디렉토리 |
| `XDG_RUNTIME_DIR_FIXED` | `/run/user/$(id -u)` | 실행 user 기준 표준 경로. 실행 환경에 세팅되어 전달됨 |

---

## 5. 저장소(repository) 관리

대상 저장소는 **내부 변수 목록(`REPO_LIST`)** 으로 관리하여 확장/변경이 쉽습니다.

| 저장소 |
|--------|
| `ocp4/release` |
| `ocp4/operator` |
| `ocp4/infra` |
| `ocp5/release` |
| `ocp5/operator` |
| `ocp5/infra` |

- **목록 선택**: `repo` 인자를 생략하면 번호로 선택합니다.
- **직접 지정**: `repo` 인자로 목록에 있는 값을 입력하면 그대로 사용합니다.
- **관리되지 않는 값**: 목록에 없는 값을 입력하면 오류 처리 후 선택 가능한 목록을 안내합니다.
- 저장소를 추가/변경하려면 스크립트의 `REPO_LIST` 배열만 수정하면 됩니다.

전송 대상은 `docker://<REGISTRY_HOST>/<repo>` 형식이 됩니다. (예: `docker://ocprgst.bss.skt:5000/ocp4/release`)

---

## 6. 사용 예시

```bash
# 저장소를 목록에서 선택 (repo 생략)
./d2m.sh ./imagesetconfig-release-4.22.10 ./relase-4.22.10

# 저장소를 직접 지정
./d2m.sh ./imagesetconfig-release-4.22.10 ./relase-4.22.10 ocp4/release
```

실제 실행되는 명령(예):

```bash
oc-mirror --config ./imagesetconfig-release-4.22.10 --from file://./relase-4.22.10 \
          docker://ocprgst.bss.skt:5000/ocp4/release --v2 \
          --cache-dir /data/ocp-file-mirror/cache
```

---

## 7. 인증 및 환경변수 처리

oc-mirror v2는 인증 파일로 `${XDG_RUNTIME_DIR}/containers/auth.json`을 **내부적으로 참조**합니다. 실행 중 `XDG_RUNTIME_DIR`이 비면 인증 정보를 잃어 권한 오류가 발생합니다.

이 도구는 이를 **근본적으로 해결**하기 위해 다음을 적용합니다.

1. **`XDG_RUNTIME_DIR`을 실행 user 기준으로 세팅**: 실행 환경에 `XDG_RUNTIME_DIR=/run/user/$(id -u)`를 명시적으로 세팅하여 oc-mirror가 올바른 인증 경로를 찾도록 합니다. (해당 명령 실행 환경에만 적용, 부모/현재 셸 미변경)
2. **`REGISTRY_AUTH_FILE` unset**: 이 변수가 설정되어 있으면 oc-mirror가 오류를 낼 수 있어, 해당 명령 실행 환경에서만 unset 합니다.

> **사전 준비**: `podman login ocprgst.bss.skt:5000` 등으로 `${XDG_RUNTIME_DIR}/containers/auth.json`에 인증 token이 저장되어 있어야 합니다. `XDG_RUNTIME_DIR`이 정상 세팅된 상태에서 로그인하면 이 파일에 token이 추가됩니다. 이미 인증서 파일이 있다면 해당 경로로 복사해 두어도 됩니다.

---

## 8. 실행 전 Information 출력

`oc-mirror` 실행 직전에 다음 정보가 출력됩니다.

```
==================== [Information] ====================
  도구 이름          : d2m.sh
  oc-mirror 버전     : (oc-mirror version 결과)
  config(yaml)       : ./imagesetconfig-release-4.22.10
  disk 경로(from)    : ./relase-4.22.10
  대상 registry      : docker://ocprgst.bss.skt:5000/ocp4/release
  cache 경로         : /data/ocp-file-mirror/cache
  XDG_RUNTIME_DIR    : /run/user/1000 (실행 환경에 세팅)
  인증(auth.json)    : /run/user/1000/containers/auth.json
  REGISTRY_AUTH_FILE : 이 명령 실행 환경에서 unset 처리
  실행 명령어        :
    oc-mirror --config ... --from file://... docker://... --v2 --cache-dir ...
======================================================
```

---

## 9. 정상 완료 후 cluster-resources 후처리 (name 중복 방지)

`oc-mirror` 가 정상 완료(종료코드 0)되면, oc-mirror 가 자동 생성하는 `<disk_path>/working-dir/cluster-resources/` 아래 YAML 에 대해 **name 중복 방지 후처리** 를 수행합니다.

release 는 버전별로 ImageSetConfiguration 을 별도로 만들기 때문에, 여러 버전을 같은 registry 에 저장하면 `signature-configmap.yaml` 의 `name` 이 충돌할 수 있습니다. 이를 방지하기 위해 `name` 값을 유니크하게 수정합니다. (`itms-*` / `idms-*` 는 중복이 허용되며, Operator 는 catalog index 로 처리되어 별도 조치가 필요 없습니다.)

**어떤 처리를 할지는 `disk_path` 의 마지막 폴더명으로 판단합니다.**

| disk_path 마지막 폴더명 | 대상 파일 | 처리 내용 |
|-------------------------|-----------|-----------|
| `additionalimages-nosignature` (개별 이미지) | `itms*.yaml` (각 파일별) | `itms*.yaml.origin` 으로 백업 후, `metadata.name` 값에 `-nosignature` 접미사 부여 |
| 그 외 (release 등) | `signature-configmap.yaml` | `signature-configmap.yaml.origin` 으로 백업 후, `metadata.name` 값에 `-<disk_path 마지막 폴더명>` 접미사 부여 |

### 동작 규칙

- 수정 전 원본을 항상 `<파일>.origin` 으로 백업합니다.
- `metadata:` 블록 아래 **첫 번째 `name:` 값만** 수정하며, 들여쓰기·기타 필드(namespace 등)는 그대로 보존합니다.
- 이미 `<파일>.origin` 백업이 존재하면 **재실행으로 간주하여 건너뜁니다.** (접미사 중복 부착 방지)
- 후처리는 미러링 성공 후에만 실행되며, 후처리 중 일부 오류가 발생해도 미러링 종료코드에는 영향을 주지 않고 경고만 출력합니다.

### 예시

```
# disk_path 의 마지막 폴더명이 release-4.22.10 인 경우
metadata:
  name: signature-configmap            # 수정 전
  name: signature-configmap-release-4.22.10   # 수정 후

# disk_path 의 마지막 폴더명이 additionalimages-nosignature 인 경우
metadata:
  name: itms-generic-0                 # 수정 전
  name: itms-generic-0-nosignature     # 수정 후
```

---

## 10. 화면 출력(색상) 처리

색상 코드 정의(`C_RED`, `C_GREEN`, `C_YELLOW`, `C_CYAN`, `C_WHITE`, `C_BOLD` 등)는 유지하되, 일부 터미널에서 글씨가 안 보이는 문제를 피하기 위해 **화면 출력은 모두 `C_BOLD`(굵게)로 통일** 되어 있습니다.

- 나중에 특정 메시지를 색상으로 표시하고 싶으면, 해당 `printf` 의 `${C_BOLD}` 를 원하는 색상 변수(예: `${C_GREEN}`)로 수동 변경하면 됩니다.

---

## 11. 종료 코드

| 코드 | 의미 |
|------|------|
| 0 | 미러링 성공 |
| 1 | 인자 오류 / 저장소 오류 / 사전 점검 실패 |
| 그 외 | `oc-mirror` 실행 실패 (oc-mirror 반환 코드 전달) |

---

## 12. 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| `oc-mirror 명령을 찾을 수 없습니다` | 미설치/PATH 누락 | oc-mirror v2 설치 및 PATH 등록 |
| `관리되지 않는 저장소입니다` | 목록 외 repo 입력 | 안내된 목록에서 선택하거나 `REPO_LIST`에 추가 |
| `인증 파일이 없습니다` (경고) | XDG 경로에 auth.json 없음 | `podman login ${REGISTRY_HOST}`로 로그인하거나 인증서파일을 `${XDG_RUNTIME_DIR}/containers/auth.json`로 복사 |
| 인증 권한 오류 | XDG_RUNTIME_DIR 초기화로 인증 유실 | 본 도구는 XDG_RUNTIME_DIR을 `/run/user/$(id -u)`로 세팅하여 회피. 해당 경로에 auth.json 존재 확인 |
| 서명 관련 오류 | 서명 없는 이미지 | 서명 포함/skip은 다운로드 단계(m2d)에서 결정됩니다. `m2d.sh --skip-signature`로 다시 내려받으세요 |

---

## 관련 도구

| 도구 | 역할 |
|------|------|
| `m2d.sh` | mirror-to-disk (인터넷망 → 디스크) |
| `d2m.sh` | disk-to-mirror (디스크 → private registry) |

---

## 변경이력

| 버전 | 날짜 | 변경내용 | 작성자 |
|------|------|----------|--------|
| v1.0 | 2026-08-16 | 최초 작성 | k.s.k & kiro |
| v1.1 | 2026-08-16 | 저장소명 오타 수정(relese → release) | k.s.k & kiro |
| v1.2 | 2026-08-16 | 불필요한 --skip-signature 옵션 제거 (서명 처리는 m2d 다운로드 단계에서 결정) | k.s.k & kiro |
| v1.3 | 2026-08-16 | 인증 방식 개선: --authfile 강제 대신 XDG_RUNTIME_DIR을 실행 user 기준으로 세팅, --authfile은 선택 옵션 | k.s.k & kiro |
| v1.4 | 2026-08-16 | --authfile 옵션 완전 제거(XDG_RUNTIME_DIR 방식 일원화), 인증 파일 부재 안내 메시지 수정 | k.s.k & kiro |
| v1.5 | 2026-09-07 | 정상 완료 후 cluster-resources 후처리 추가(signature-configmap.yaml name 유니크화 / additionalimages-nosignature 의 itms*.yaml name 에 -nosignature 부여), 화면 출력 C_BOLD 통일, print_warn 헬퍼 추가 | k.s.k & kiro |
