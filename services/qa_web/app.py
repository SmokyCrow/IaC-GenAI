#!/usr/bin/env python3
"""QA Web service

Lightweight QA UI (server-side rendered) that talks to Results API.
It does not implement the layering orchestrator, only fetches existing
artifacts and allows marking QA status via Results API endpoints.

For simplicity we keep an in-memory QA map here and POST back to
Results API (future: persist in DB). This avoids adding Postgres now.
"""
from __future__ import annotations

import os
import json
from typing import Dict, Any
from pathlib import Path

import httpx
import asyncio
from fastapi import FastAPI, Request, Form, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.staticfiles import StaticFiles

RESULTS_API_URL = os.environ.get("RESULTS_API_URL", "http://results-api.semseg.svc.cluster.local")

app = FastAPI(title="QA Web", version="0.1.0")

STATIC_DIR = Path(__file__).parent / "static"
STATIC_DIR.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

QA_STATE: Dict[str, Dict[str, Any]] = {}

BASE_TEMPLATE = """<!doctype html><html><head><meta charset='utf-8'/>
<title>QA Web</title>
<style>
body{{font-family:system-ui,Arial,sans-serif;margin:1.5rem;color:#222}}
table{{border-collapse:collapse;width:100%;margin-top:1rem}}
th,td{{border:1px solid #ccc;padding:4px 6px;font-size:0.85rem}}
th{{background:#f5f5f5}}
.ok{{color:#2d862d}}.warn{{color:#c77a00}}.bad{{color:#b30000}}
a{{text-decoration:none;color:#0366d6}}
form.inline{{display:inline}}
code{{background:#f0f0f0;padding:2px 4px;border-radius:3px}}
</style></head><body>{body}</body></html>"""


async def fetch_json(path: str):
    url = f"{RESULTS_API_URL.rstrip('/')}{path}"
    async with httpx.AsyncClient(timeout=10) as client:
        r = await client.get(url)
        if r.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Upstream {path} returned {r.status_code}")
        return r.json()


def render(body: str) -> HTMLResponse:
    return HTMLResponse(BASE_TEMPLATE.format(body=body))


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.get("/")
async def index():
    frames_doc = await fetch_json("/frames")
    frames = frames_doc.get("frames", [])
    rows = []
    for f in frames:
        fid = f.get("frame_id")
        has = f.get("has", {})
        summary = f.get("summary", {})
        qa = QA_STATE.get(fid, {}).get("status", "-")
        lf = summary.get("labeled_fraction") if summary else None
        lf_pct = f"{lf*100:.1f}%" if isinstance(lf,(int,float)) else "?"
        flags = summary.get("flags", {}) if summary else {}
        cls = "ok"
        if flags.get("low_coverage"):
            cls = "warn"
        if flags.get("head_missing") and flags.get("hands_missing"):
            cls = "bad"
        rows.append(
            f"<tr><td><a href='/frames/{fid}'>{fid}</a></td>"
            f"<td class='{cls}'>{lf_pct}</td>"
            f"<td>{'Y' if has.get('labels') else ''}</td>"
            f"<td>{'Y' if has.get('metrics') else ''}</td>"
            f"<td>{'Y' if has.get('anonymized') else ''}</td>"
            f"<td>{qa}</td>"
            f"<td>"
            f"<form class='inline' method='post' action='/frames/{fid}/qa'><input type='hidden' name='status' value='accepted'><button>✓</button></form>"
            f"<form class='inline' method='post' action='/frames/{fid}/qa'><input type='hidden' name='status' value='rejected'><button>✗</button></form>"
            f"</td></tr>"
        )
    body = "<h1>QA Frames</h1><table><tr><th>Frame</th><th>Coverage</th><th>Lbl</th><th>Met</th><th>Anon</th><th>QA</th><th>Actions</th></tr>" + "".join(rows) + "</table>"
    return render(body)


@app.get("/frames/{frame_id}")
async def frame_detail(frame_id: str, kind: str = "metrics"):
    seg = None
    try:
        labels = await fetch_json(f"/frames/{frame_id}/labels.json")
    except HTTPException:
        labels = None
    try:
        metrics = await fetch_json(f"/frames/{frame_id}/metrics.json")
    except HTTPException:
        metrics = None
    qa = QA_STATE.get(frame_id, {}).get("status", "-")
    body = f"<h1>Frame {frame_id}</h1><p>QA status: <strong>{qa}</strong></p>"
    # Navigation bar
    nav = (
        "<p>Views: "
        f"<a href='/frames/{frame_id}?kind=metrics'>metrics</a> | "
        f"<a href='/frames/{frame_id}?kind=labels'>labels</a> | "
    ""
        f"<a href='/frames/{frame_id}?kind=preview'>preview</a> | "
        f"<a href='/frames/{frame_id}?kind=anonymized'>anonymized</a> | "
        f"<a href='/frames/{frame_id}?kind=labels-colored'>labels-colored</a> | "
        f"<a href='/frames/{frame_id}?kind=compare'>compare</a>"
        "</p>"
    )
    body += nav
    if metrics:
        lf = metrics.get("totals", {}).get("labeled_fraction")
        body += f"<p>Labeled fraction: {lf*100:.2f}%</p>" if isinstance(lf,(int,float)) else ""
        flags = metrics.get("flags", {})
        body += "<pre>" + json.dumps(flags, indent=2) + "</pre>"
    if kind == "labels" and labels:
        # Prefer the colored labels preview when viewing labels
        body += f"<h2>Labels</h2><img src='/proxy/{frame_id}/preview-labels-colored.png' style='max-width:480px;border:1px solid #ccc;float:right;margin:0 0 1rem 1rem' alt='preview missing'/><pre>" + json.dumps(labels.get("labels", {}), indent=2) + "</pre><div style='clear:both'></div>"
    
    elif kind == "preview":
        body += f"<h2>Preview</h2><img src='/proxy/{frame_id}/preview.png?t=1' style='max-width:640px;border:1px solid #ccc' alt='preview missing'/>"
    elif kind == "anonymized":
        body += (
            f"<h2>Anonymized Cloud</h2><p><code>.ply</code> download via proxy: "
            f"<a href='/proxy/{frame_id}/anonymized.ply' download>anonymized-{frame_id}.ply</a></p>"
            f"<p>Anonymized Preview:<br><img src='/proxy/{frame_id}/preview-anonymized.png?t=anon' style='max-width:640px;border:1px solid #ccc' alt='preview missing'/></p>"
        )
    elif kind == "labels-colored":
        body += (
            f"<h2>Colorized Labels PLY</h2><p><a href='/proxy/{frame_id}/labels-colored.ply' download>labels-colored-{frame_id}.ply</a></p>"
            f"<p>Labels-colored Preview:<br><img src='/proxy/{frame_id}/preview-labels-colored.png?t=lbl' style='max-width:640px;border:1px solid #ccc' alt='preview missing'/></p>"
        )
    elif kind == "compare":
        # Build side-by-side comparison (generic, labels-colored, anonymized)
        body += "<h2>Comparison</h2>"
        imgs = [
            ("Original/Generic", f"/proxy/{frame_id}/preview.png?t=cmp"),
            ("Labels-Colored", f"/proxy/{frame_id}/preview-labels-colored.png?t=cmp"),
            ("Anonymized", f"/proxy/{frame_id}/preview-anonymized.png?t=cmp"),
        ]
        grid = "<table style='width:100%;text-align:center'><tr>" + "".join([f"<th>{title}</th>" for title,_ in imgs]) + "</tr><tr>" + \
               "".join([f"<td><img src='{src}' style='max-width:100%;border:1px solid #ccc' alt='{title} missing'/></td>" for title,src in imgs]) + "</tr></table>"
        body += grid
    else:
        if metrics:
            body += "<h2>Metrics</h2><pre>" + json.dumps(metrics, indent=2) + "</pre>"
    body += "<p><a href='/'>&larr; Back</a></p>"
    return render(body)


@app.post("/frames/{frame_id}/qa")
async def set_qa(frame_id: str, status: str = Form(...)):
    if status not in {"accepted", "rejected"}:
        raise HTTPException(status_code=400, detail="Invalid status")
    QA_STATE[frame_id] = {"status": status}
    return RedirectResponse(url="/", status_code=303)


@app.get("/api/qa")
async def qa_dump():
    return {"qa": QA_STATE}


@app.get("/proxy/{frame_id}/{artifact}")
async def proxy_artifact(frame_id: str, artifact: str):
    # Allow fixed set of artifact names
    allowed = {"labels.json","metrics.json","anonymized.ply","labels-colored.ply","preview.png","preview-anonymized.png","preview-labels-colored.png"}
    if artifact not in allowed:
        raise HTTPException(status_code=400, detail="Unsupported artifact")
    upstream_path = f"/frames/{frame_id}/{artifact}"
    url = f"{RESULTS_API_URL.rstrip('/')}{upstream_path}"
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.get(url)
            if r.status_code != 200:
                raise HTTPException(status_code=r.status_code, detail=f"Upstream returned {r.status_code}")
            media = r.headers.get("content-type", "application/octet-stream")
            disp = "inline"
            filename = artifact
            if artifact == 'anonymized.ply':
                filename = f"anonymized-{frame_id}.ply"
            elif artifact == 'labels-colored.ply':
                filename = f"labels-colored-{frame_id}.ply"
            if filename.endswith('.ply'):
                disp = "attachment"
            return Response(content=r.content, media_type=media, headers={
                "Content-Disposition": f"{disp}; filename={filename}"
            })
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Proxy fetch failed: {e}")
