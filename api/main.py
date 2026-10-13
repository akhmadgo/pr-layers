from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from classifier import classify_files
from dotenv import load_dotenv
import os

load_dotenv()

app = FastAPI(title="Zeroth API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


class FileInput(BaseModel):
    path: str
    patch: Optional[str] = None


class AnalyzeRequest(BaseModel):
    files: list[FileInput]
    pr_title: Optional[str] = None


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/analyze")
async def analyze(req: AnalyzeRequest):
    if not req.files:
        raise HTTPException(400, "No files provided")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise HTTPException(500, "ANTHROPIC_API_KEY not configured")
    return await classify_files(req.files, req.pr_title)
