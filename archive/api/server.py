#!/usr/bin/env python3
"""
OCP 관리도구 (octools) - FastAPI REST API 서버
Windows Streamlit UI에서 원격으로 oc 명령어를 실행하기 위한 API 서버.

사용법:
    uvicorn api.server:app --host 0.0.0.0 --port 8000
    또는
    ./run_api.sh
"""

import os
import sys

# 프로젝트 루트를 path에 추가
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional

from api.routes import router

app = FastAPI(
    title="OCP 관리도구 API",
    description="OpenShift Container Platform 관리도구 REST API",
    version="1.0.0",
)

# CORS 설정 (Windows 클라이언트 접근 허용)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 운영 시 특정 IP로 제한 권장
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 라우터 등록
app.include_router(router, prefix="/api")


@app.get("/")
def root():
    """API 서버 루트"""
    return {
        "service": "OCP 관리도구 API",
        "version": "1.0.0",
        "docs": "/docs",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
