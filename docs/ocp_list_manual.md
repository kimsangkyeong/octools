# ocp_list.sh 사용자 매뉴얼

| 항목 | 내용 |
|------|------|
| 프로그램 | `ocp_list.sh` |
| 식별자 | `[ocpcatalog]` |
| 문서버전 | v1.4 |
| 작성일 | 2026-09-07 |
| 작성자 | k.s.k & kiro |

---

## 1. 개요

`ocp_list.sh`는 OpenShift(OCP) 운영자가 **버전 업그레이드를 계획**할 때 사용하는 카탈로그 조회 및 영향도 분석 도구입니다. 두 축의 기능을 제공합니다.

1. **카탈로그 조회 (전체 목록)**
   - OCP 버전(예: 4.21, 4.22)별 **release 목록**을 조회하여 JSON/TXT로 저장
   - **Operator 카탈로그(index)** 를 `opm render`(공식)로 조회하여 패키지별 default 채널/최신 버전을 표로 정리
2. **Operator 업그레이드 영향도 분석**
   - 설치된 Operator를 선택(또는 수동 입력)하고, 여러 OCP 버전을 기준으로 채널/min/max/현재버전/판정을 표로 비교
   - 결과를 `check-operator-version.txt`로 저장하여 내부 리뷰·의사결정 자료로 활용

---

## 2. 사전 요구사항

| 도구 | 용도 | 필수 여부 |
|------|------|-----------|
| `bash` | 스크립트 실행 | 필수 |
| `jq` | JSON 파싱 | 필수 |
| `opm` | Operator 카탈로그(index) 조회 | Operator 기능 사용 시 필수 |
| `oc` | 클러스터 현재 버전/설치 Operator 조회 | 클러스터 연동 시 필요 |
| `curl` | release(Cincinnati) 조회 | Release 기능 사용 시 필요 |

> 시작 시 의존성(`jq` 필수 / `opm`,`oc` 권장)을 점검하여 안내합니다.
> 레지스트리 접근을 위해 사전 `podman login registry.redhat.io` 또는 pull secret 설정이 필요할 수 있습니다.

---

## 3. 설치 및 실행

```bash
chmod +x ocp_list.sh
./ocp_list.sh
```

- 결과 저장 루트는 기본 `$HOME/workdir/ocpcatalogs` 이며, 프로그램 내 `WORKDIR` 변수 또는 메뉴 `4) 설정`에서 변경할 수 있습니다.
- 시그널(`Ctrl+C` 등) 발생 시 로그가 `$HOME/tmp/ocp_list.sh.log`에 기록됩니다.

---

## 4. 저장 디렉토리 구조

버전 입력값 기준으로 `ocp<버전>` 하위 폴더가 생성됩니다.

```
$HOME/workdir/ocpcatalogs/
├── ocp4.20/
│   ├── release.json                  # release 원본(JSON)
│   ├── release.txt                   # release 표(default=stable 채널)
│   ├── redhat-operator-index.json    # opm render 원본
│   ├── redhat-operator-index.txt     # 패키지별 default 채널/최신 버전 표
│   └── check-operator-version.txt    # 영향도 분석(컬럼: 4.20,4.21,4.22)
├── ocp4.21/
│   └── check-operator-version.txt    # 영향도 분석(컬럼: 4.21,4.22)
└── ocp4.22/
    └── (비교 대상 없음 → check 파일 미생성)
```

---

## 5. 메뉴 구성

```
1) OCP Release 목록 조회
2) Operator 카탈로그(index) 조회
3) Operator 업그레이드 영향도 분석
4) 설정 보기/변경
q) 종료
```

### 5.1 OCP Release 목록 조회 (메뉴 1)

- OCP 버전(예: `4.22`)과 arch(기본 `amd64`)를 입력합니다.
- OpenShift Update Service(Cincinnati) graph API로 `stable/fast/eus/candidate` 채널을 조회합니다.
  - 실행문 예: `curl -sH 'Accept: application/json' 'https://api.openshift.com/api/upgrades_info/v1/graph?channel=stable-4.22&arch=amd64'`
- 산출물
  - `release.json`: 채널별 원본 응답 병합 + 조회 메타
  - `release.txt`: default(stable) 채널 기준 버전 표 + 채널별 버전 개수 요약

### 5.2 Operator 카탈로그(index) 조회 (메뉴 2)

- OCP 버전과 카탈로그 index를 지정합니다.
  - index는 목록에서 선택하거나(예: `redhat-operator-index`) 직접 입력할 수 있습니다.
- `opm render`로 카탈로그를 조회합니다.
  - 실행문 예: `opm render registry.redhat.io/redhat/redhat-operator-index:v4.22 > <index>.json`
- 산출물
  - `<index>.json`: opm render 원본 스트림
  - `<index>.txt`: 패키지별 **DEFAULT_CHANNEL**, **DEFAULT_CHANNEL_HEAD(최신 버전)**, **DESCRIPTION(패키지 용도)** 표 + 요약

### 5.3 Operator 업그레이드 영향도 분석 (메뉴 3)

이 도구의 핵심 기능입니다. 절차는 다음과 같습니다.

0. **클러스터 사용 여부 확인 + oc 로그인 사전 점검**
   - 분석 진입 시 "클러스터에 연결하여 진행할지"를 먼저 묻습니다.
   - `[Y] 예`를 선택하면 **oc 로그인 여부를 사전 점검**합니다.
     - 로그인되어 있으면 그대로 진행합니다.
     - 미로그인 시 로그인 방법을 안내하고, 별도 터미널에서 로그인한 뒤 `[r] 재확인` / `[s] 건너뛰기(오프라인)` / `[b] 취소`를 선택할 수 있습니다.
     - 이 사전 점검 덕분에 미로그인 상태에서 발생하는 원시 에러 메시지가 노출되지 않습니다.
   - `[n] 아니오`를 선택하면 오프라인 모드로 package/버전을 수동 입력합니다.
1. **대상 Operator 선택**
   - 클러스터 사용 모드이면 `oc get subscription -A`로 설치된 Operator 목록을 조회해 **2분할/페이지 메뉴**로 표시합니다.
   - 선택 방법: 번호(콤마/공백으로 복수), `a`(전체 선택), `m`(목록에 없는 것도 콤마로 수동 입력)
   - 오프라인 모드이면 package 이름을 콤마로 직접 입력합니다.
2. **분석 카탈로그 index 지정** (기본 `redhat-operator-index`)
3. **비교할 OCP 버전 입력** (콤마 복수, 예: `4.20,4.21,4.22`)
   - 현재 클러스터 버전이 있으면 함께 안내합니다.
4. 각 버전 카탈로그를 확보(없으면 `opm render`)하고 표를 생성합니다.

#### 결과 표 컬럼

| 컬럼 | 설명 |
|------|------|
표는 **2단 헤더**로 구성되어 가독성을 높입니다.

- **1단(상위 헤더)**: `PACKAGE`, `DESCRIPTION`, 각 **OCP release 버전**, `CURRENT(ch/csv)`
- **2단(하위 서브헤더)**: 각 OCP 버전 아래에 `CHANNEL`, `MINVERSION`, `MAXVERSION`, `VERDICT`

각 Operator 행은 해당 OCP 버전 블록의 서브 항목(채널/최소/최대/판정)에 값만 표시하여, 어떤 버전에서 어떤 채널·버전 범위인지 한눈에 비교할 수 있습니다.

| 컬럼 | 설명 |
|------|------|
| PACKAGE | Operator 패키지 이름 |
| DESCRIPTION | 패키지 역할 간단 설명(카탈로그 description) |
| OCP <버전> > CHANNEL | 해당 OCP 버전 카탈로그의 defaultChannel |
| OCP <버전> > MINVERSION | 해당 채널의 최소 버전 |
| OCP <버전> > MAXVERSION | 해당 채널의 head(최신 버전) |
| OCP <버전> > VERDICT | 현재 설치 버전 기준 판정 |
| CURRENT(ch/csv) | 클러스터에 설치된 현재 채널/버전(csv). 미설치면 `-/-` |

#### OCP 호환성 속성 (opm render 의 olm.bundle.properties 기반)

| 속성 | 설명 |
|------|------|
| `olm.maxOpenShiftVersion` (maxOCP) | 이 값을 초과하는 OCP로는 클러스터 업그레이드가 **차단**됨. Operator 개발사가 선언 |
| `olm.openshift.versions` (support) | Operator가 지원/호환되는 OCP 버전 범위 (예: `v4.14-v4.17`, `>=4.14`) |

- 두 속성은 **head 번들 기준**으로 추출하되, 설치버전(csv) 번들이 대상 카탈로그에 있으면 **그 번들 값을 우선** 사용합니다.
- 속성이 **없으면 `none`으로 치환**하며, 이 경우 채널/semver 기준 판정으로 폴백합니다.

#### 판정(Verdict) 의미 (위에서부터 우선 적용)

| 판정 | 의미 |
|------|------|
| 미지원(대안필요) | 대상 버전 카탈로그에 해당 패키지가 없음 → 대체 Operator 검토 필요 |
| 업그레이드차단 | `maxOCP`(≠none)이고 대상 OCP > maxOCP → 이 Operator가 상위 OCP 업그레이드를 차단 |
| 호환범위밖 | `support`(≠none) 범위에 대상 OCP가 포함되지 않음 |
| 채널변경필요 | 현재 채널이 대상 버전의 defaultChannel과 달라 채널 변경 필요 |
| 업그레이드필요 | 현재 버전이 대상 채널의 최소 버전보다 낮아 업그레이드가 필요 |
| 유지가능 | 현재 설치 버전이 대상 버전 카탈로그의 채널 범위(min~max) 내에 있음 |
| 확인필요 | 현재 버전 미상 또는 버전 파싱 불가 등으로 수동 확인 필요 |

#### 파일 저장 규칙 (요구사항 반영)

여러 버전을 비교할 때, **최하위 버전 폴더부터** 상위 버전을 컬럼으로 배치하여 각 폴더에 저장합니다.

- `4.20, 4.21, 4.22` 비교 시
  - `ocp4.20/check-operator-version.txt` → 컬럼: 4.20, 4.21, 4.22
  - `ocp4.21/check-operator-version.txt` → 컬럼: 4.21, 4.22
  - `ocp4.22/` → 비교 대상 없음 → **파일 미생성**
- 파일 첫 부분에 **생성 날짜/시간/OS user** 정보가 기록됩니다.

---

## 6. 결과 파일의 Information 섹션

모든 TXT 산출물 상단에는 **어떤 명령으로 기초 데이터를 조회했는지**를 알려주는 `[Information]` 섹션이 포함됩니다. 이를 통해 결과를 검증하거나 직접 재현할 수 있습니다.

- `release.txt` : Cincinnati graph API `curl` 조회 명령, 채널 목록 명시
- `<index>.txt` : `opm render <image> | jq . > <index>.json` 조회 명령, DEFAULT_CHANNEL/HEAD 산출 기준 명시
- `check-operator-version.txt` : 카탈로그 조회 명령(`opm render`), 설치 Operator 조회 명령(`oc get subscription`), 컬럼 산출 기준, **판정(Verdict) 로직 기준**을 모두 명시

또한 **모든 JSON 산출물은 `jq`로 pretty-print**되어 사람이 읽기 좋은 형태로 저장됩니다.

### check-operator-version.txt 예시

```
# Operator Upgrade Impact Analysis
# generated_at : 2026-08-16 14:20:03   os_user: kskim
# base_version : 4.20   (기준 버전 폴더)
# compare_cols : 4.20 4.21 4.22
# catalog_index: redhat-operator-index
# cluster_now  : 4.20.15
#
# ==============================================================================
# [Information] 기초 데이터 조회 방법
#   - 카탈로그 조회 : opm render registry.redhat.io/redhat/redhat-operator-index:v<버전> | jq . > <버전>/redhat-operator-index.json
#   - 설치 Operator : oc get subscription -A -o json
#                     (package=.spec.name, 현재채널=.spec.channel, 설치버전=.status.currentCSV)
#   - 클러스터 버전 : oc get clusterversion version -o jsonpath='{.status.desired.version}'
#
# [Information] 컬럼/값 산출 기준
#   - defaultChannel : olm.package.defaultChannel
#   - min            : defaultChannel entries 중 semver 최소
#   - max(head)      : replaces/skips 대상이 아닌 최신 번들(채널 head)
#   - CURRENT        : 설치된 현재 채널/버전(csv)
#
# [Information] OCP 호환성 속성 (olm.bundle.properties)
#   - maxOCP  : olm.maxOpenShiftVersion (초과 OCP 업그레이드 차단), 없으면 none
#   - support : olm.openshift.versions  (지원 OCP 범위), 없으면 none
#
# [Information] 판정(Verdict) 로직 기준 (위에서부터 우선 적용)
#   - 미지원(대안필요) : 대상 카탈로그에 package 없음
#   - 업그레이드차단   : maxOCP(!=none) 이고 대상 OCP > maxOCP
#   - 호환범위밖       : support(!=none) 범위에 대상 OCP 없음
#   - 채널변경필요     : 현재 채널 != 대상 defaultChannel
#   - 업그레이드필요   : 현재버전 < 대상 채널 min
#   - 유지가능         : 현재버전이 [min, max] 범위 내
# ==============================================================================
#
                                       |                        | OCP 4.20                                      | OCP 4.21                                      | OCP 4.22                                      | 
PACKAGE            | DESCRIPTION            | CHANNEL    MINVER  MAXVER  VERDICT             | CHANNEL    MINVER  MAXVER  VERDICT             | CHANNEL    MINVER  MAXVER  VERDICT             | CURRENT(ch/csv)
-------------------+------------------------+-----------------------------------------------+-----------------------------------------------+-----------------------------------------------+----------------
cluster-logging    | Logging for OpenShift  | stable-6.0 6.0.0   6.0.3   유지가능            | stable-6.1 6.1.0   6.1.2   업그레이드필요      | -          -       -       미지원(대안필요)    | stable-6.0/6.0.2
```

- 상단 헤더는 OCP release 버전, 하단 서브헤더는 CHANNEL/MINVER/MAXVER/VERDICT로 구성됩니다.
- 위 예시에서 `OCP 4.22`에 해당 package가 없으면 VERDICT는 `미지원(대안필요)`, `maxOCP`가 대상 OCP보다 낮으면 `업그레이드차단`이 표시됩니다.

---

## 7. 확장 방법

- **카탈로그 index 추가**: 스크립트 상단 `CATALOG_INDEXES` 배열에 index 이미지명을 추가하면 선택 목록에 반영됩니다.
- **레지스트리 변경**: `REG_BASE` 변수 또는 메뉴 `4) 설정`에서 변경.
- **release 조회 채널 조정**: `func_release_catalog`의 `channels` 변수에서 조회할 채널을 조정.

---

## 8. 화면 출력(색상) 처리

색상 코드 정의(`C_RED`, `C_GREEN`, `C_YELLOW`, `C_BLUE`, `C_CYAN`, `C_WHITE`, `C_BOLD`)는 유지하되, 일부 터미널에서 글씨가 안 보이는 문제를 피하기 위해 **화면 출력은 모두 `C_BOLD`(굵게)로 통일** 되어 있습니다.

- 대상: 타이틀 배너, 실행문 표시, 메뉴/프롬프트, 경고/오류 메시지 등 모든 출력.
- 나중에 특정 메시지를 색상으로 표시하고 싶으면, 해당 `printf` 의 `${C_BOLD}` 를 원하는 색상 변수(예: `${C_GREEN}`)로 수동 변경하면 됩니다.

---

## 9. 주의사항

| 항목 | 설명 |
|------|------|
| 레지스트리 인증 | `registry.redhat.io` 접근에는 pull secret/podman login이 필요할 수 있습니다. |
| opm 조회 시간 | 카탈로그가 커서 `opm render`가 수 분 소요될 수 있습니다. 결과 JSON은 재사용(캐시)됩니다. |
| 판정의 성격 | Verdict는 카탈로그 메타데이터 기반의 사전 참고용입니다. 실제 업그레이드 전 Red Hat 공식 문서/릴리스 노트를 함께 확인하세요. |
| min/max 계산 | defaultChannel의 entries에서 semver 정렬 최소값과 head(다른 항목의 replaces/skips 대상이 아닌 최신)로 산출합니다. |

---

## 변경이력

| 버전 | 날짜 | 변경내용 | 작성자 |
|------|------|----------|--------|
| v1.0 | 2026-08-16 | 최초 작성 | k.s.k & kiro |
| v1.1 | 2026-08-16 | 영향도 분석 진입 시 클러스터 사용 여부 확인 + oc 로그인 사전 점검/가이드(재확인 루프) 추가 | k.s.k & kiro |
| v1.2 | 2026-08-16 | JSON은 jq pretty-print 저장, TXT에 조회 명령어/판정 로직 기준 Information 섹션 추가 | k.s.k & kiro |
| v1.3 | 2026-08-16 | olm.maxOpenShiftVersion/olm.openshift.versions 기반 호환성 판정(업그레이드차단/호환범위밖) 추가, 속성 없으면 none 폴백 | k.s.k & kiro |
<<<<<<< HEAD
| v1.4 | 2026-09-07 | operator catalog txt에 DESCRIPTION 컬럼 추가, 영향도 비교 표를 2단 헤더(OCP버전 / CHANNEL·MINVER·MAXVER·VERDICT)로 개선 | k.s.k & kiro |
=======
| v1.4 | 2026-09-07 | 화면 출력을 C_BOLD 로 통일(색상 정의는 유지, 가독성 문제 회피. 필요 시 수동으로 색상 변경) | k.s.k & kiro |
>>>>>>> 97e32b59074e66f86bc5323c68bfc9ff543fe5b5
