
#!/usr/bin/env python3
"""Redactor: recolor/remove PII (head, hands) using labels; publishes s_redacted_done."""

import argparse
import json
import logging
import os
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import sys
# Ensure repository root on sys.path so 'services.*' imports work
ROOT_DIR = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(ROOT_DIR)) if str(ROOT_DIR) not in sys.path else None

import numpy as np
from plyfile import PlyData
from services.common.preview import generate_preview

# Fail-fast imports for Redis helpers (required)
REDIS_IMPORT_ERR: Optional[Exception] = None
try:  # pragma: no cover
	from services.common.redis_bus import get_client, ensure_group, readgroup_blocking, xack_safe, xadd_safe  # type: ignore
except Exception as _e:  # pragma: no cover
	REDIS_IMPORT_ERR = _e; get_client = ensure_group = readgroup_blocking = xack_safe = xadd_safe = None  # type: ignore

LOGGER = logging.getLogger("redactor")

PII_LABELS = ["head", "hand_left", "hand_right"]
ANONYMIZED_COLOR = (128, 128, 128)  # Gray for anonymized regions

def load_json(path: Path) -> Dict:
	with path.open("r", encoding="utf-8") as fh:
		return json.load(fh)

def load_ply(path: Path) -> Tuple[np.ndarray, np.ndarray]:
	pd = PlyData.read(path.as_posix())
	vx = pd["vertex"].data
	xs = np.asarray(vx["x"], dtype=np.float32)
	ys = np.asarray(vx["y"], dtype=np.float32)
	zs = np.asarray(vx["z"], dtype=np.float32)
	points = np.stack([xs, ys, zs], axis=1)
	if all(c in vx.dtype.names for c in ("red", "green", "blue")):
		colors = np.stack([np.asarray(vx["red"], dtype=np.uint8), np.asarray(vx["green"], dtype=np.uint8), np.asarray(vx["blue"], dtype=np.uint8)], axis=1)
	else:
		colors = np.full_like(points, 200, dtype=np.uint8)
	return points.astype(np.float32), colors.astype(np.uint8)

def write_ply(path: Path, points: np.ndarray, colors: np.ndarray) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	tmp = path.with_suffix(path.suffix + f".{os.getpid()}.{int(time.time()*1000)}.tmp")
	with tmp.open("w", encoding="utf-8") as fh:
		fh.write("ply\nformat ascii 1.0\n"); fh.write(f"element vertex {points.shape[0]}\n")
		fh.write("property float x\nproperty float y\nproperty float z\n")
		fh.write("property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n")
		for (x, y, z), (r, g, b) in zip(points, colors): fh.write(f"{x} {y} {z} {int(r)} {int(g)} {int(b)}\n")
	try:
		if path.exists():
			try: tmp.unlink()
			except FileNotFoundError: pass
			return
		tmp.replace(path)
	finally:
		try:
			if tmp.exists(): tmp.unlink()
		except Exception: pass

def _expand_bbox(b: Dict[str, float], margin: float = 0.0) -> Dict[str, float]:
	return b if margin <= 0 else {"xmin": float(b["xmin"]) - margin, "xmax": float(b["xmax"]) + margin, "ymin": float(b["ymin"]) - margin, "ymax": float(b["ymax"]) + margin, **({"zmin": float(b.get("zmin",0))-margin, "zmax": float(b.get("zmax",0))+margin} if "zmin" in b and "zmax" in b else {})}



def redact_frame(frame_id: str, ply_path: Path, labels_path: Path, out_path: Path, mode: str = "recolor") -> bool:
	points, colors = load_ply(ply_path)
	labels = load_json(labels_path)
	total_points = points.shape[0]
	mask = np.zeros(total_points, dtype=bool)
	for label_name in PII_LABELS:
		bbox = (labels.get("labels", {}).get(label_name) or {}).get("bbox")
		if not bbox: continue
		bbox = _expand_bbox(bbox, margin=0.01)
		xy = ((points[:,0] >= bbox["xmin"]) & (points[:,0] <= bbox["xmax"]) & (points[:,1] >= bbox["ymin"]) & (points[:,1] <= bbox["ymax"]))
		zok = (points[:,2] >= bbox["zmin"]) & (points[:,2] <= bbox["zmax"]) if ("zmin" in bbox and "zmax" in bbox) else True
		mask |= (xy & zok)
	if mode == "remove": points, colors = points[~mask], colors[~mask]
	else: colors[mask] = np.array(ANONYMIZED_COLOR, dtype=np.uint8)
	write_ply(out_path, points, colors)
	LOGGER.info(f"Redacted frame {frame_id}: {np.sum(mask)} PII points {'removed' if mode=='remove' else 'recolored'}.")
	preview_path = out_path.parent / f"preview-anonymized-{frame_id}.png"
	generate_preview(points, colors, preview_path, logger=LOGGER)
	return True



def run_loop(args: argparse.Namespace) -> None:
	in_dir = Path(args.in_dir)
	labels_dir = Path(args.labels_dir)
	out_dir = Path(args.out_dir)
	# no readiness sentinel or tmp cleanup; keep the core loop lean
	# Redis-only mode: fail fast on missing helpers or config
	if REDIS_IMPORT_ERR is not None or any(x is None for x in (get_client, ensure_group, readgroup_blocking, xack_safe, xadd_safe)):
		LOGGER.error("redactor: redis helpers unavailable: %s", REDIS_IMPORT_ERR)
		return
	r = get_client(args.redis_url)
	if not r or not args.redis_in_stream:
		LOGGER.error("redactor: Redis URL/stream required; exiting")
		return
	# Be explicit in logs so it's visible even if group already exists
	LOGGER.info("redactor: ensuring Redis group %s on stream %s", args.redis_group, args.redis_in_stream)
	ensure_group(r, args.redis_in_stream, args.redis_group)
	LOGGER.info("redactor: Redis group %s is ready on %s", args.redis_group, args.redis_in_stream)
	while True:
		entries = readgroup_blocking(
			r,
			args.redis_in_stream,
			args.redis_group,
			args.redis_consumer,
			count=1,
			block_ms=int(args.poll_interval * 1000),
		)
		if not entries: continue
		_, messages = entries[0]
		for msg_id, fields in messages:
			frame_id = fields.get("frame_id")
			ply_path = Path(fields.get("ply_path") or (in_dir / f"{frame_id}.ply").as_posix())
			labels_path = Path(fields.get("labels_path") or (labels_dir / f"labels-{frame_id}.json").as_posix())
			out_path = out_dir / f"anonymized-{frame_id}.ply"
			try:
				if out_path.exists(): xack_safe(r, args.redis_in_stream, args.redis_group, msg_id); continue
				# Wait for files to exist and be older than min-age (avoid racing)
				start = time.monotonic()
				deadline = start + max(2.0, args.min_age * 4)
				while True:
					now = time.monotonic()
					if ply_path.exists() and labels_path.exists():
						try:
							ok_age = ((time.time()-ply_path.stat().st_mtime) >= args.min_age and (time.time()-labels_path.stat().st_mtime) >= args.min_age)
						except FileNotFoundError:
							ok_age = False
						if ok_age: break
					if now >= deadline:
						LOGGER.debug("Artifacts not ready for %s; will retry later", frame_id); raise RuntimeError("Artifacts not ready")
					time.sleep(min(0.2, args.poll_interval))
				redact_frame(frame_id, ply_path, labels_path, out_path, mode=args.mode)
				# Publish redacted done (optional)
				if args.redis_out_stream and r is not None:
					xadd_safe(r, args.redis_out_stream, {"frame_id": frame_id, "anonymized_path": out_path.as_posix()})
				xack_safe(r, args.redis_in_stream, args.redis_group, msg_id)
			except Exception:
				LOGGER.exception("Failed to redact frame %s", frame_id)
				# Leave unacked for retry

def parse_args() -> argparse.Namespace:
	p = argparse.ArgumentParser(description="Redactor service")
	p.add_argument("--in-dir", default="/pc-frames", help="Directory with merged PLY frames")
	p.add_argument("--labels-dir", default="/segments", help="Directory with labels-*.json from part labeler")
	p.add_argument("--out-dir", default="/segments", help="Directory for anonymized-*.ply output")
	p.add_argument("--mode", choices=["recolor","remove"], default="recolor", help="PII handling: recolor or remove points")
	p.add_argument("--poll-interval", type=float, default=1.0, help="Polling interval in seconds")
	p.add_argument("--min-age", type=float, default=0.5, help="Minimum age in seconds before processing a file")
	p.add_argument("--log-level", choices=["debug","info","warning","error"], default="info")
	p.add_argument("--redis-url", default=os.environ.get("REDIS_URL",""), help="Redis URL")
	p.add_argument("--redis-in-stream", default=os.environ.get("REDIS_STREAM_PARTS_LABELED","s_parts_labeled"), help="Stream to consume labels events from")
	p.add_argument("--redis-out-stream", default=os.environ.get("REDIS_STREAM_REDACTED_DONE","s_redacted_done"), help="Stream to publish redacted done events to")
	p.add_argument("--redis-group", default=os.environ.get("REDIS_GROUP_REDACTOR","g_redactor"), help="Consumer group name")
	p.add_argument("--redis-consumer", default=os.environ.get("HOSTNAME","redactor-1"), help="Consumer name")
	# Redis-only; no filesystem fallback
	return p.parse_args()

def main() -> None:
	args = parse_args()
	logging.basicConfig(
		level=getattr(logging, args.log_level.upper()),
		format="%(asctime)s.%(msecs)03d %(levelname)s %(name)s: %(message)s",
		datefmt="%Y-%m-%d %H:%M:%S",
	)
	LOGGER.info(
		"Starting redactor | in=%s labels=%s out=%s mode=%s",
		args.in_dir,
		args.labels_dir,
		args.out_dir,
		args.mode,
	)
	run_loop(args)

if __name__ == "__main__":
	main()
