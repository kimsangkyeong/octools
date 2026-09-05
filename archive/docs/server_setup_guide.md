# OCP 관리도구 (octools) 서버 구성 가이드

| 항목 | 내용 |
|------|------|
| 문서버전 | v1.0 |
| 작성일 | 2026-08-16 |
| 작성자 | Kiro |

---

## 1. 전체 구성 개요

```
┌─────────────────────────────────────────────────────────────┐
│              Linux Server (OCP 접속 환경)                      │
│                                                              │
│   [1] CLI 직접 사용 (SSH 접속)                                │
│   [2] FastAPI 서버 (포트 8000) → Windows에서 원격 호출         │
│                                                              │
│   필수 조건:                                                  │
│   - oc CLI 설치 및 oc login 완료                              │
│   - Python 3.8+                                              │
│   - 방화벽: 8000 포트 개방 (API 서버용)                        │
└──────────────────────────────────┬───────────────────────────┘
                                   │ HTTP (포트 8000)
                                   │
┌──────────────────────────────────┴───────────────────────────┐
│              Windows Client                                    │
│                                                               │
│   Streamlit UI (로컬 실행)                                     │
│   - API 서버 URL 설정 후 사용                                  │
│                                                               │
│   필수 조건:                                                   │
│   - Python 3.8+                                               │
│   - streamlit, requests 패키지                                 │
└───────────────────────────────────────────────────────────────┘
```

---

## 2. Linux 서버 구성

### 2.1 사전 요구사항

| 항목 | 요구사항 |
|------|----------|
| OS | RHEL 8/9, CentOS 8/9, Rocky Linux 8/9 |
| Python | 3.8 이상 |
| oc CLI | OpenShift CLI 설치 및 클러스터 로그인 완료 |
| 네트워크 | 8000 포트 외부 접근 허용 |

### 2.2 Python 설치 확인

```bash
# Python 버전 확인
python3 --version

# Python이 없는 경우 설치 (RHEL/CentOS)
sudo dnf install python3 python3-pip -y
```

### 2.3 프로젝트 설치

```bash
# 프로젝트 클론 또는 복사
cd /opt
git clone <repository-url> octools
# 또는 직접 복사
# scp -r octools/ user@server:/opt/octools/

cd /opt/octools

# Python 가상환경 생성 (권장)
python3 -m venv venv
source venv/bin/activate

# 서버 의존성 설치
pip install -r requirements.txt
```

### 2.4 oc CLI 설정 확인

```bash
# oc 설치 확인
oc version

# 클러스터 로그인 확인
oc whoami
oc get nodes

# 로그인이 안 된 경우
oc login https://<api-server>:6443 -u <username> -p <password>
# 또는 토큰 사용
oc login --token=<token> --server=https://<api-server>:6443
```

### 2.5 CLI 프로그램 실행 (직접 사용)

```bash
cd /opt/octools

# 실행 권한 부여
chmod +x run_cli.sh

# CLI 실행
./run_cli.sh
```

---

## 3. API 서버 구성 (원격 호출용)

### 3.1 API 서버 실행 (개발/테스트)

```bash
cd /opt/octools
source venv/bin/activate

# 직접 실행
chmod +x run_api.sh
./run_api.sh

# 또는 수동 실행
uvicorn api.server:app --host 0.0.0.0 --port 8000

# 포트 변경 시
./run_api.sh 9000
```

### 3.2 API 서버 확인

```bash
# 로컬 테스트
curl http://localhost:8000/api/health
# 응답: {"status":"healthy","service":"octools-api"}

# 메뉴 목록 조회
curl http://localhost:8000/api/menus

# 명령어 실행 테스트
curl -X POST http://localhost:8000/api/execute \
  -H "Content-Type: application/json" \
  -d '{"menu_id": "node_list"}'
```

### 3.3 systemd 서비스 등록 (운영 환경)

API 서버를 시스템 서비스로 등록하여 자동 시작되도록 설정한다.

```bash
# 서비스 파일 생성
sudo vi /etc/systemd/system/octools-api.service
```

```ini
[Unit]
Description=OCP Management Tool API Server
After=network.target

[Service]
Type=simple
User=octools
Group=octools
WorkingDirectory=/opt/octools
Environment=PATH=/opt/octools/venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/opt/octools/venv/bin/uvicorn api.server:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
# 서비스 등록 및 시작
sudo systemctl daemon-reload
sudo systemctl enable octools-api
sudo systemctl start octools-api

# 상태 확인
sudo systemctl status octools-api

# 로그 확인
sudo journalctl -u octools-api -f
```

### 3.4 방화벽 설정

```bash
# firewalld 사용 시
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload

# 확인
sudo firewall-cmd --list-ports
```

### 3.5 Nginx 리버스 프록시 설정 (선택사항)

HTTPS 적용이나 추가 보안이 필요한 경우 Nginx를 프록시로 사용한다.

```bash
# Nginx 설치
sudo dnf install nginx -y

# 설정 파일 생성
sudo vi /etc/nginx/conf.d/octools.conf
```

```nginx
server {
    listen 443 ssl;
    server_name octools.example.com;

    ssl_certificate /etc/pki/tls/certs/octools.crt;
    ssl_certificate_key /etc/pki/tls/private/octools.key;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }
}

# HTTP → HTTPS 리다이렉트
server {
    listen 80;
    server_name octools.example.com;
    return 301 https://$host$request_uri;
}
```

```bash
# Nginx 시작
sudo systemctl enable nginx
sudo systemctl start nginx

# 방화벽에 HTTPS 추가
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

---

## 4. Windows 클라이언트 구성

### 4.1 사전 요구사항

| 항목 | 요구사항 |
|------|----------|
| OS | Windows 10/11 |
| Python | 3.8 이상 |
| 네트워크 | Linux 서버 8000 포트 접근 가능 |

### 4.2 Python 설치

```powershell
# Python 설치 확인
python --version

# 설치가 안 된 경우 공식 사이트에서 다운로드
# https://www.python.org/downloads/
# 설치 시 "Add Python to PATH" 체크
```

### 4.3 프로젝트 설치 및 실행

```powershell
# 프로젝트 폴더로 이동
cd C:\octools

# 가상환경 생성 (권장)
python -m venv venv
.\venv\Scripts\Activate.ps1

# UI 의존성 설치
pip install -r requirements-ui.txt

# Streamlit UI 실행
streamlit run ui/app.py
```

### 4.4 서버 연결 설정

Streamlit UI가 브라우저에서 열리면:
1. 사이드바 상단의 "API 서버 URL" 입력란에 Linux 서버 주소 입력
2. 형식: `http://<서버IP>:8000`
3. 연결 상태가 "● 서버 연결됨"으로 표시되면 정상

### 4.5 바탕화면 바로가기 생성 (선택)

```powershell
# run_ui.bat 파일 생성
@echo off
cd C:\octools
call venv\Scripts\activate.bat
streamlit run ui/app.py
pause
```

---

## 5. 네트워크 구성 체크리스트

| # | 확인사항 | 확인방법 |
|---|----------|----------|
| 1 | Linux → OCP API 접근 가능 | `oc get nodes` 정상 응답 |
| 2 | API 서버 포트(8000) 리스닝 | `ss -tlnp \| grep 8000` |
| 3 | 방화벽 8000 포트 허용 | `firewall-cmd --list-ports` |
| 4 | Windows → Linux 네트워크 연결 | `ping <서버IP>` |
| 5 | Windows → API 서버 접근 | 브라우저에서 `http://<서버IP>:8000/docs` 접속 |

---

## 6. 보안 권장사항

### 6.1 API 토큰 인증 (선택)

운영 환경에서는 API 접근에 토큰 인증을 적용할 수 있다.

환경변수로 토큰을 설정:
```bash
# Linux 서버 (.env 파일 또는 systemd 설정)
export OCTOOLS_API_TOKEN="your-secret-token-here"
```

### 6.2 접근 IP 제한

```bash
# firewalld rich rule로 특정 IP만 허용
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" port port="8000" protocol="tcp" accept'
sudo firewall-cmd --reload
```

### 6.3 oc 서비스 계정 사용

운영 환경에서는 개인 계정 대신 서비스 계정(SA)으로 oc login하여 최소 권한만 부여한다.

```bash
# 서비스 계정 토큰으로 로그인
oc login --token=$(oc sa get-token octools-sa -n octools-system) --server=https://api.cluster.example.com:6443
```

---

## 7. 문제 해결 (Troubleshooting)

| 증상 | 원인 | 해결 |
|------|------|------|
| "oc 명령어를 찾을 수 없습니다" | oc CLI 미설치 또는 PATH 누락 | oc 설치 후 PATH 등록 |
| API 서버 연결 실패 | 서버 미실행 또는 방화벽 차단 | systemctl 확인, 방화벽 확인 |
| "Unauthorized" 에러 | oc 로그인 만료 | `oc login` 재실행 |
| 명령어 실행 시간 초과 | 클러스터 응답 지연 | 네트워크 확인, timeout 조정 |
| Streamlit 실행 안 됨 | 의존성 미설치 | `pip install -r requirements-ui.txt` |

---

## 8. 운영 체크리스트

### 최초 설치 시

- [ ] Linux 서버에 Python 3.8+ 설치
- [ ] oc CLI 설치 및 클러스터 로그인
- [ ] 프로젝트 파일 배포 (/opt/octools)
- [ ] Python 가상환경 생성 및 의존성 설치
- [ ] API 서버 실행 테스트 (curl)
- [ ] systemd 서비스 등록
- [ ] 방화벽 포트 개방
- [ ] Windows 클라이언트에서 접속 테스트

### 일일 점검

- [ ] API 서버 구동 상태 확인
- [ ] oc login 세션 유효성 확인
- [ ] 로그 확인 (`journalctl -u octools-api --since today`)

---

## 변경이력

| 버전 | 날짜 | 변경내용 | 작성자 |
|------|------|----------|--------|
| v1.0 | 2026-08-16 | 최초 작성 | Kiro |
