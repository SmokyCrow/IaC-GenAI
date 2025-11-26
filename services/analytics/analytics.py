#!/usr/bin/env python3
"""Analytics: read labels-<id>.json, compute metrics-<id>.json, publish s_analytics_done (Redis-driven)."""

from __future__ import annotations

import argparse
import json
import logging
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple

import sys
ROOT_DIR = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(ROOT_DIR)) if str(ROOT_DIR) not in sys.path else None

from services.common.redis_bus import get_client, ensure_group, readgroup_blocking, xack_safe, xadd_safe  # type: ignore


LOGGER = logging.getLogger("analytics")


def load_json(path: Path) -> Dict:
    with path.open("r", encoding="utf-8") as fh: return json.load(fh)


def save_json_atomic(path: Path, data: Dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fh: json.dump(data, fh)
    tmp.replace(path)


def bbox_center(bbox: Dict[str, float]) -> Optional[Tuple[float, float, float]]:
    try:
        cx = (float(bbox["xmin"]) + float(bbox["xmax"])) / 2.0
        cy = (float(bbox["ymin"]) + float(bbox["ymax"])) / 2.0
        zmin, zmax = bbox.get("zmin"), bbox.get("zmax")
        cz = (float(zmin) + float(zmax)) / 2.0 if (zmin is not None and zmax is not None) else 0.0
        return (cx, cy, cz)
    except Exception:
        return None


def bbox_volume(bbox: Dict[str, float]) -> Optional[float]:
    try:
        dx = max(0.0, float(bbox["xmax"]) - float(bbox["xmin"]))
        dy = max(0.0, float(bbox["ymax"]) - float(bbox["ymin"]))
        zmin, zmax = bbox.get("zmin"), bbox.get("zmax")
        if zmin is None or zmax is None: return None
        dz = max(0.0, float(zmax) - float(zmin)); vol = dx * dy * dz
        return vol if vol > 0 else None
    except Exception:
        return None


def compute_analytics(labels_doc: Dict, prev_doc: Optional[Dict], low_cov_threshold: float) -> Dict:
    frame_id = labels_doc.get("frame_id")
    labels = labels_doc.get("labels", {})
    base_metrics = labels_doc.get("metrics", {})

    totals = {
        "total_points": int(base_metrics.get("total_points", 0)),
        "labeled_points": int(base_metrics.get("labeled_points", 0)),
        "labeled_fraction": float(base_metrics.get("labeled_fraction", 0.0)),
    }

    per_part: Dict[str, Dict] = {}
    for name, entry in labels.items():
        count = int(entry.get("point_count", 0))
        frac = float(entry.get("fraction", 0.0))
        bbox = entry.get("bbox") or {}
        center = bbox_center(bbox) if bbox else None
        volume = bbox_volume(bbox) if bbox else None
        density = (count / volume) if (volume and volume > 0) else None
        per_part[name] = {
            "point_count": count,
            "fraction": frac,
            "bbox": bbox if bbox else None,
            "center": {"x": center[0], "y": center[1], "z": center[2]} if center else None,
            "volume": volume,
            "density": density,
        }

    flags = {
        "low_coverage": totals["labeled_fraction"] < low_cov_threshold,
        "head_missing": int(per_part.get("head", {}).get("point_count", 0)) == 0,
        "hands_missing": (per_part.get("hand_left", {}).get("point_count", 0) == 0)
        and (per_part.get("hand_right", {}).get("point_count", 0) == 0),
    }

    motion: Dict[str, float] = {}
    if prev_doc:
        prev_parts = prev_doc.get("per_part", {})
        for name, cur in per_part.items():
            c = cur.get("center")
            p = prev_parts.get(name, {}).get("center")
            if c and p:
                dx = float(c["x"]) - float(p["x"])  # type: ignore[index]
                dy = float(c["y"]) - float(p["y"])  # type: ignore[index]
                dz = float(c["z"]) - float(p["z"])  # type: ignore[index]
                motion[name] = float((dx * dx + dy * dy + dz * dz) ** 0.5)

    return {
        "frame_id": frame_id,
        "totals": totals,
        "per_part": per_part,
        "flags": flags,
        "motion": motion if motion else None,
    }


def run_loop(args: argparse.Namespace) -> None:
    seg_dir = Path(args.segments_dir)
    out_dir = Path(args.out_dir)
    # no readiness sentinel; event-driven via Redis

    # Redis required; fail fast if missing
    if not args.redis_url or not args.redis_in_stream:
        LOGGER.error("analytics: Redis URL and input stream are required")
        sys.exit(1)
    r = get_client(args.redis_url)
    if r is None:
        LOGGER.error("analytics: unable to connect to Redis at %s", args.redis_url)
        sys.exit(1)
    # Explicit INFO so startup intent is clear even if groups already exist
    LOGGER.info("analytics: ensuring Redis group %s on stream %s", args.redis_group, args.redis_in_stream)
    ensure_group(r, args.redis_in_stream, args.redis_group)
    LOGGER.info("analytics: Redis group %s is ready on %s", args.redis_group, args.redis_in_stream)
    LOGGER.info("analytics: Redis mode enabled (consuming %s)", args.redis_in_stream)

    poll_ms = max(200, int(args.poll_interval * 1000))
    while True:
        entries = readgroup_blocking(r, args.redis_in_stream, args.redis_group, args.redis_consumer, count=1, block_ms=poll_ms)
        if not entries:
            continue
        _, messages = entries[0]
        for msg_id, fields in messages:
            frame_id = fields.get("frame_id")
            if not frame_id:
                xack_safe(r, args.redis_in_stream, args.redis_group, msg_id)
                continue
            labels_path = seg_dir / f"labels-{frame_id}.json"
            metrics_path = out_dir / f"metrics-{frame_id}.json"
            try:
                if metrics_path.exists():
                    # idempotent
                    xack_safe(r, args.redis_in_stream, args.redis_group, msg_id)
                    continue
                # wait for labels to exist and be older than min-age
                start = time.monotonic()
                deadline = start + max(2.0, args.min_age * 4)
                while True:
                    now = time.monotonic()
                    if labels_path.exists():
                        try:
                            ok_age = (time.time() - labels_path.stat().st_mtime) >= args.min_age
                        except FileNotFoundError:
                            ok_age = False
                        if ok_age:
                            break
                    if now >= deadline:
                        raise FileNotFoundError("labels not found or too new")
                    time.sleep(0.05)

                labels_doc = load_json(labels_path)
                prev_doc = None
                try:
                    fid = int(str(frame_id)); prev_path = out_dir / f"metrics-{fid-1:05d}.json"
                    prev_doc = load_json(prev_path) if prev_path.exists() else None
                except Exception:
                    pass

                analytics = compute_analytics(labels_doc, prev_doc, args.low_coverage_threshold)
                save_json_atomic(metrics_path, analytics)
                LOGGER.info("analytics: wrote %s", metrics_path.name)

                # publish done
                if args.redis_out_stream:
                    xadd_safe(
                        r,
                        args.redis_out_stream,
                        {"frame_id": str(frame_id), "metrics_path": metrics_path.as_posix()},
                    )
                xack_safe(r, args.redis_in_stream, args.redis_group, msg_id)
            except Exception as e:
                LOGGER.warning("analytics: failed for frame %s: %s", frame_id, e)
                # leave unacked for retry


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Analytics service")
    p.add_argument("--segments-dir", default="/segments", help="Directory containing labels-*.json")
    p.add_argument("--out-dir", default="/segments", help="Directory to write metrics-*.json")
    # No filesystem fallback; Redis-only
    p.add_argument("--poll-interval", type=float, default=1.0, help="Polling interval seconds")
    p.add_argument("--min-age", type=float, default=0.5, help="Minimum file age before processing")
    p.add_argument("--low-coverage-threshold", type=float, default=0.2, help="QoS threshold for low coverage flag")
    p.add_argument("--log-level", choices=["debug","info","warning","error"], default="info")
    p.add_argument("--redis-url", default=os.environ.get("REDIS_URL",""), help="Redis URL")
    p.add_argument("--redis-in-stream", default=os.environ.get("REDIS_STREAM_PARTS_LABELED","s_parts_labeled"), help="Stream to consume s_parts_labeled events from")
    p.add_argument("--redis-out-stream", default=os.environ.get("REDIS_STREAM_ANALYTICS_DONE","s_analytics_done"), help="Stream to publish s_analytics_done events to")
    p.add_argument("--redis-group", default=os.environ.get("REDIS_GROUP_ANALYTICS","g_analytics"), help="Consumer group")
    p.add_argument("--redis-consumer", default=os.environ.get("HOSTNAME","analytics-1"), help="Consumer name")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    logging.basicConfig(level=getattr(logging, args.log_level.upper()), format="%(asctime)s %(levelname)s %(message)s")
    run_loop(args)


if __name__ == "__main__":
    main()
