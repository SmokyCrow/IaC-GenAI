#!/usr/bin/env python3

import os
import re
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, UploadFile, File, Request, HTTPException, Header
from fastapi.responses import JSONResponse


OUT_DIR_ENV = "INGEST_OUT_DIR"
DEFAULT_OUT_DIR = "/sub-pc-frames"


def get_out_dir() -> str:
    out_dir = os.getenv(OUT_DIR_ENV, DEFAULT_OUT_DIR); Path(out_dir).mkdir(parents=True, exist_ok=True); return out_dir


def sanitize_frame_id(frame_id: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_\-]+", frame_id): raise HTTPException(status_code=400, detail="Invalid frame_id")
    return frame_id


def to_int(value: Optional[str], default: int = 0) -> int:
    try: return int(value) if value is not None else default
    except ValueError: raise HTTPException(status_code=400, detail="Invalid layer id")


async def write_stream_to_file(dest_path: Path, upload: Optional[UploadFile], body: Optional[bytes]) -> None:
    tmp_path = dest_path.with_suffix(dest_path.suffix + ".tmp")
    try:
        with open(tmp_path, "wb") as f:
            if upload is not None:
                while True:
                    chunk = await upload.read(1024 * 1024)
                    if not chunk: break
                    f.write(chunk)
            elif body: f.write(body)
            else: raise HTTPException(status_code=400, detail="Empty upload payload")
        tmp_path.replace(dest_path)
    finally:
        try:
            if tmp_path.exists(): tmp_path.unlink(missing_ok=True)
        except Exception: pass


app = FastAPI(title="Ingest API", version="0.1.0")


@app.get("/healthz")
async def healthz(): return {"status": "ok"}


@app.post("/frames/{frame_id}")
async def upload_single_frame(
    frame_id: str,
    request: Request,
    file: Optional[UploadFile] = File(default=None),
    x_layer_id: Optional[str] = Header(default=None, convert_underscores=True),
):
    """
    Upload a single DRC for a frame. Stored as 0-<frame_id>.drc by default.
    Accepts either multipart/form-data (file field) or raw application/octet-stream body.
    Optional header X-Layer-Id can override the default layer id (0).
    """
    out_dir = Path(get_out_dir())
    frame_id = sanitize_frame_id(frame_id)
    layer = to_int(x_layer_id, default=0)

    payload: Optional[bytes] = None
    if file is None:
        payload = await request.body()
        if not payload:
            raise HTTPException(status_code=400, detail="No upload payload provided")

    dest = out_dir / f"{layer}-{frame_id}.drc"
    await write_stream_to_file(dest, file, payload)
    return JSONResponse(status_code=201, content={
        "stored": str(dest),
        "layer": layer,
        "frame_id": frame_id
    })


@app.post("/tiles/{layer}/{frame_id}")
async def upload_tiled(
    layer: int,
    frame_id: str,
    request: Request,
    file: Optional[UploadFile] = File(default=None),
):
    """
    Upload a DRC tile for a given layer and frame.
    Stored as <layer>-<frame_id>.drc under the output directory.
    Accepts either multipart/form-data (file field) or raw application/octet-stream body.
    """
    out_dir = Path(get_out_dir())
    frame_id = sanitize_frame_id(frame_id)
    layer = to_int(str(layer))

    payload: Optional[bytes] = None
    if file is None:
        payload = await request.body()
        if not payload:
            raise HTTPException(status_code=400, detail="No upload payload provided")

    dest = out_dir / f"{layer}-{frame_id}.drc"
    await write_stream_to_file(dest, file, payload)
    return JSONResponse(status_code=201, content={
        "stored": str(dest),
        "layer": layer,
        "frame_id": frame_id
    })


if __name__ == "__main__":
    # Run with: python services/ingest_api/ingest_api.py
    # or: uvicorn services.ingest_api.ingest_api:app --host 0.0.0.0 --port 8080
    import uvicorn

    uvicorn.run(
        "services.ingest_api.ingest_api:app",
        host="0.0.0.0",
        port=8080,
        reload=False,
    )

