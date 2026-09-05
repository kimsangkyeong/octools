# OCP 관리도구 (octools) 요구사항 문서

| 항목 | 내용 |
|------|------|
| 문서버전 | v1.1 |
| 작성일 | 2026-08-16 |
| 작성자 | Kiro |

---

## 1. 프로젝트 개요

OpenShift Container Platform(OCP) 운영 환경에서 `oc` CLI 명령어를 활용한 클러스터 관리도구를 개발한다.

- **Linux 환경**: Python 기반 CLI 인터랙티브 메뉴 프로그램
- **Windows 환경**: Streamlit 기반 웹 UI로 원격 서버의 동일 기능 호출

---

## 2. 기능 요구사항

### FR-01. OCP 리소스 조회
| ID | 설명 |
|----|------|
| FR-01-1 | `oc` 명령어를 통해 Pod, ClusterOperator(co), MachineConfig(mc), MachineConfigPool(mcp) 등 운영 리소스 조회 |
| FR-01-2 | 비정상 상태(NotReady, CrashLoopBackOff, Error 등)의 리소스 라인을 빨강색으로 강조 표시 |

### FR-02. 메뉴 기반 인터페이스
| ID | 설명 |
|----|------|
| FR-02-1 | Linux CLI: 커서(cursor) 이동 또는 번호 입력으로 메뉴 선택 후 명령어 실행 및 결과 출력 |
| FR-02-2 | Windows UI: Streamlit 웹 인터페이스에서 마우스 클릭으로 메뉴 선택 |
| FR-02-3 | Linux/Windows 메뉴 종류는 동일하게 유지 |

### FR-03. 확장 가능한 메뉴 구조
| ID | 설명 |
|----|------|
| FR-03-1 | 메뉴 항목은 함수(function) 형식으로 등록하여 기능 추가가 용이한 플러그인 구조 |
| FR-03-2 | 메뉴 정의 파일(config)에 항목을 추가하면 자동으로 CLI/UI에 반영 |

### FR-04. 화면 이분할 및 페이지 관리
| ID | 설명 |
|----|------|
| FR-04-1 | 메뉴가 많아질 경우 화면을 좌/우 또는 상/하 이분할하여 메뉴 목록 표시 |
| FR-04-2 | 페이지 이동(이전/다음) 기능으로 다수 메뉴 탐색 가능 |

### FR-05. 서브메뉴 (Namespace 선택 + Pod 선택)
| ID | 설명 |
|----|------|
| FR-05-1 | `oc get pod -A` (전체) / `oc get pod -n <ns>` (특정) 중 선택 가능 |
| FR-05-2 | Enter 입력 시 `oc get ns`로 namespace 목록을 추출하고 서브메뉴로 선택 제공 |
| FR-05-3 | namespace 선택형 명령어에 대해 동일한 서브메뉴 패턴 적용 |
| FR-05-4 | Pod 선택이 필요한 메뉴(예: Pod 로그)는 NS 선택 후 Pod 목록 서브메뉴 추가 제공 |
| FR-05-5 | Pod 서브메뉴에서 Pod 이름, 상태, Restart 수를 표시하여 선택 편의성 제공 |

### FR-06. 초기 메뉴 (17개)
| # | 메뉴명 | 명령어/스크립트 | NS선택 | POD선택 |
|---|--------|----------------|--------|---------|
| 1 | Pod 조회 | `pod_list.sh` | O | X |
| 2 | Pod 상태 상세 | `pod_wide.sh` | O | X |
| 3 | Pod 로그 조회 | `pod_logs.sh` | O | O |
| 4 | 컨테이너 이미지 목록 | `container_images.sh` | O | X |
| 5 | Deployment 조회 | `deployment_list.sh` | O | X |
| 6 | Node 상태 조회 | `node_list.sh` | X | X |
| 7 | ClusterOperator 조회 | `co_list.sh` | X | X |
| 8 | MachineConfig 조회 | `mc_list.sh` | X | X |
| 9 | MachineConfigPool 조회 | `mcp_list.sh` | X | X |
| 10 | CatalogSource 조회 | `catalogsource_list.sh` | O | X |
| 11 | Subscription 조회 | `subscription_list.sh` | O | X |
| 12 | Service 조회 | `svc_list.sh` | O | X |
| 13 | Route 조회 | `route_list.sh` | O | X |
| 14 | PVC 조회 | `pvc_list.sh` | O | X |
| 15 | NS 리소스 종합조회 | `ns_resources.sh` | O | X |
| 16 | Event 조회 | `event_list.sh` | O | X |
| 17 | CSR 조회 | `csr_list.sh` | X | X |

### FR-08. Namespace 리소스 종합조회
| ID | 설명 |
|----|------|
| FR-08-1 | 특정 NS 선택 시 Pod, Deployment, Service, DaemonSet, ConfigMap, StatefulSet, Secret을 한 화면에 출력 |
| FR-08-2 | SA(ServiceAccount)를 사용하는 리소스(Pod, Deploy, STS, DS)에는 SA 컬럼을 함께 표시 |
| FR-08-3 | 각 리소스 섹션을 구분 헤더로 분리하고 리소스 수 요약 표시 |

### FR-07. 원격 호출 (Windows → Linux)
| ID | 설명 |
|----|------|
| FR-07-1 | Windows Streamlit UI에서 Linux 서버의 oc 명령어를 원격 실행 |
| FR-07-2 | Linux 서버에 REST API 서버(FastAPI)를 구성하여 명령어 실행 결과 반환 |
| FR-07-3 | 웹서버 구성 및 배포 가이드 제공 |

---

## 3. 비기능 요구사항

| ID | 항목 | 설명 |
|----|------|------|
| NFR-01 | 성능 | 명령어 실행 결과는 5초 이내 응답 (네트워크 제외) |
| NFR-02 | 확장성 | 메뉴 추가 시 코드 수정 최소화 (설정 파일 + 함수 추가만으로 확장) |
| NFR-03 | 가용성 | API 서버 장애 시 에러 메시지 표시 및 재시도 안내 |
| NFR-04 | 보안 | API 서버 접근 시 기본 인증(토큰) 적용 가능 구조 |
| NFR-05 | 호환성 | Python 3.8+ 지원, RHEL/CentOS 계열 Linux 호환 |

---

## 4. 제약사항

| # | 내용 |
|---|------|
| 1 | `oc` CLI가 Linux 서버에 사전 설치 및 로그인(oc login) 되어 있어야 함 |
| 2 | Windows에서 직접 oc 명령 실행 불가 → REST API를 통한 원격 호출 필수 |
| 3 | 프로그래밍 언어: bash, python |
| 4 | 문서 산출물: md + pdf |

---

## 5. 시스템 구성도

```
┌─────────────────────────────────────────────────────────────┐
│                    Linux Server (OCP)                         │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │  CLI Program │    │  FastAPI     │    │   oc CLI     │   │
│  │  (Python)    │───▶│  REST API    │───▶│  (명령실행)   │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│         ▲                    ▲                               │
│         │                    │                               │
└─────────│────────────────────│───────────────────────────────┘
          │                    │ HTTP/HTTPS
          │                    │
     [직접 실행]          ┌────┴────────────┐
                          │  Windows Client  │
                          │  Streamlit UI    │
                          └─────────────────┘
```

---

## 6. 용어 정의

| 용어 | 설명 |
|------|------|
| OCP | OpenShift Container Platform |
| oc | OpenShift CLI 명령어 도구 |
| Pod | Kubernetes/OpenShift의 최소 배포 단위 |
| CO | ClusterOperator, 클러스터 운영자 리소스 |
| MC | MachineConfig, 노드 머신 설정 리소스 |
| MCP | MachineConfigPool, 머신 설정 풀 리소스 |
| NS | Namespace, 리소스 격리 단위 |
| CSR | CertificateSigningRequest, 인증서 서명 요청 |

---

## 변경이력

| 버전 | 날짜 | 변경내용 | 작성자 |
|------|------|----------|--------|
| v1.0 | 2026-08-16 | 최초 작성 | Kiro |
| v1.1 | 2026-08-16 | Pod 로그/컨테이너이미지/CatalogSource/Subscription/NS종합조회 추가, Pod 서브메뉴 추가, 메뉴 17개로 확장 | Kiro |
