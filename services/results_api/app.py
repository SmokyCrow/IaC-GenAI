#!/usr/bin/env python3
from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Dict, List, Optional, Any

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse, FileResponse, Response

try:
    from services.common.redis_bus import get_client  # type: ignore
except Exception:
    get_client = lambda *a, **k: None  # type: ignore

SEGMENTS_DIR = Path(os.environ.get("SEGMENTS_DIR", "/segments")).resolve()

app = FastAPI(title="Results API", version="0.1.0")

# Redis (optional)
REDIS_URL = os.environ.get("REDIS_URL", "")
STREAMS: Dict[str, str] = {
    "s_frames_converted": os.environ.get("REDIS_STREAM_FRAMES_CONVERTED", os.environ.get("REDIS_STREAM_FRAMES_MERGED", "")),
    "s_parts_labeled": os.environ.get("REDIS_STREAM_PARTS_LABELED", ""),
    "s_redacted_done": os.environ.get("REDIS_STREAM_REDACTED_DONE", ""),
    "s_analytics_done": os.environ.get("REDIS_STREAM_ANALYTICS_DONE", ""),
}


def find_frame_ids() -> List[str]:
    ids = {p.stem.split("-",1)[-1] for p in SEGMENTS_DIR.glob("labels-*.json")}
    ids.update({p.stem.split("-",1)[-1] for p in SEGMENTS_DIR.glob("metrics-*.json")})
    return sorted(ids)


def artifact_paths(frame_id: str) -> Dict[str, Path]:
    return {
        "labels": SEGMENTS_DIR / f"labels-{frame_id}.json",
        "metrics": SEGMENTS_DIR / f"metrics-{frame_id}.json",
        "labels_colored": SEGMENTS_DIR / "labels" / f"labels-colored-{frame_id}.ply",
        "anonymized": SEGMENTS_DIR / f"anonymized-{frame_id}.ply",
        "preview": SEGMENTS_DIR / f"preview-{frame_id}.png",
        "preview_anonymized": SEGMENTS_DIR / f"preview-anonymized-{frame_id}.png",
        "preview_labels": SEGMENTS_DIR / f"preview-labels-colored-{frame_id}.png",
    }

"""Previews are generated upstream; API only serves existing artifacts."""



@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/frames")
def list_frames():
    frames = []
    for fid in find_frame_ids():
        ap = artifact_paths(fid)
        item: Dict[str, object] = {"frame_id": fid, "has": {k: p.exists() for k, p in ap.items()}}
        mp = ap["metrics"]
        if mp.exists():
            import json
            try:
                with mp.open("r", encoding="utf-8") as fh: m = json.load(fh)
                item["summary"] = {"labeled_fraction": m.get("totals", {}).get("labeled_fraction"), "flags": m.get("flags", {})}
            except Exception:
                pass
        frames.append(item)
    return {"frames": frames}


def _redis_client():
    if not REDIS_URL: return None
    try: return get_client(REDIS_URL)
    except Exception: return None


@app.get("/streams")
def list_streams():
    r = _redis_client(); out: List[Dict[str, Any]] = []
    for public, key in STREAMS.items():
        if not key: out.append({"name": public, "key": key, "enabled": False, "len": 0}); continue
        length = None; enabled = r is not None
        if r is not None:
            try: length = int(r.xlen(key))  # type: ignore[attr-defined]
            except Exception: length = None
        out.append({"name": public, "key": key, "enabled": enabled, "len": length})
    return {"streams": out}


@app.get("/streams/{stream_name}")
def get_stream(stream_name: str, count: int = Query(50, ge=1, le=500)):
    key = STREAMS.get(stream_name)
    if not key: raise HTTPException(status_code=404, detail="Unknown or disabled stream")
    r = _redis_client()
    if r is None: raise HTTPException(status_code=503, detail="Redis not configured")
    try:
        entries = r.xrevrange(key, max="+", min="-", count=count)  # type: ignore[attr-defined]
        out = [{"id": (eid.decode() if isinstance(eid,(bytes,bytearray)) else eid),
                "fields": { (k.decode() if isinstance(k,(bytes,bytearray)) else k): (v.decode() if isinstance(v,(bytes,bytearray)) else v) for k,v in data.items()}}
               for eid, data in entries]
        return {"name": stream_name, "key": key, "entries": out}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Redis error: {e}")


def _serve_json(path: Path) -> JSONResponse:
    if not path.exists(): raise HTTPException(status_code=404, detail="Not found")
    import json
    with path.open("r", encoding="utf-8") as fh: data = json.load(fh)
    return JSONResponse(content=data)





@app.get("/frames/{frame_id}/labels.json")
def get_labels(frame_id: str): return _serve_json(artifact_paths(frame_id)["labels"])


@app.get("/frames/{frame_id}/metrics.json")
def get_metrics(frame_id: str): return _serve_json(artifact_paths(frame_id)["metrics"])


@app.get("/frames/{frame_id}/labels-colored.ply")
def get_labels_colored(frame_id: str):
    p = artifact_paths(frame_id)["labels_colored"]
    if not p.exists(): raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(p.as_posix(), media_type="application/octet-stream", filename=p.name)


@app.get("/frames/{frame_id}/anonymized.ply")
def get_anonymized(frame_id: str):
    p = artifact_paths(frame_id)["anonymized"]
    if not p.exists(): raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(p.as_posix(), media_type="application/octet-stream", filename=p.name)


@app.get("/frames/{frame_id}/preview.png")
def get_preview(frame_id: str):
    p = artifact_paths(frame_id)["preview"]
    if not p.exists(): raise HTTPException(status_code=404, detail="Preview not found")
    return FileResponse(p.as_posix(), media_type="image/png", filename=p.name)

@app.get("/frames/{frame_id}/preview-anonymized.png")
def get_preview_anonymized(frame_id: str):
    out = artifact_paths(frame_id)["preview_anonymized"]
    if not out.exists(): raise HTTPException(status_code=404, detail="Preview anonymized not found")
    return FileResponse(out.as_posix(), media_type="image/png", filename=out.name)

@app.get("/frames/{frame_id}/preview-labels-colored.png")
def get_preview_labels_colored(frame_id: str):
    out = artifact_paths(frame_id)["preview_labels"]
    if not out.exists(): raise HTTPException(status_code=404, detail="Preview labels-colored not found")
    return FileResponse(out.as_posix(), media_type="image/png", filename=out.name)

@app.get("/frames/{frame_id}/choose")
def choose_view(frame_id: str, kind: str = Query("metrics", enum=["metrics","labels","preview","anonymized","labels-colored"])):
    paths = artifact_paths(frame_id)
    # Map kind to path
    if kind == "labels-colored": p = paths["labels_colored"]
    elif kind == "anonymized": p = paths["anonymized"]
    elif kind == "preview": p = paths["preview"]
    elif kind == "labels": return get_labels(frame_id)
    else: return get_metrics(frame_id)
    if not p.exists(): raise HTTPException(status_code=404, detail="Not found")
    media = "application/octet-stream"
    if p.suffix.lower() == ".png": media = "image/png"
    elif p.suffix.lower() == ".ply": media = "application/octet-stream"
    return FileResponse(p.as_posix(), media_type=media, filename=p.name)


