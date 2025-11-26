#!/usr/bin/env python3
"""Labels-only Part Labeler: consume frames, detect pose/PII from preview, write labels (+optional colorized), publish s_parts_labeled."""

from __future__ import annotations

import argparse
import json
import logging
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import sys
ROOT_DIR = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(ROOT_DIR)) if str(ROOT_DIR) not in sys.path else None

import numpy as np
try:
    import pyminiply as pmp  # still used elsewhere, but reader may import pyvista indirectly
except Exception:  # pragma: no cover
    pmp = None  # type: ignore
from plyfile import PlyData  # lightweight PLY reader/writer without pyvista

# Import preview helpers
try:  # pragma: no cover
    from services.common.preview import generate_preview, render_preview_rgb  # type: ignore
except Exception:  # pragma: no cover
    generate_preview = None  # type: ignore
    render_preview_rgb = None  # type: ignore

# Import Redis helpers
try:  # pragma: no cover
    from services.common.redis_bus import get_client, ensure_group, readgroup_blocking, xack_safe, xadd_safe  # type: ignore
except Exception:  # pragma: no cover
    get_client = ensure_group = readgroup_blocking = xack_safe = xadd_safe = None  # type: ignore


LOGGER = logging.getLogger("part-labeler")

from mediapipe import solutions as mp_solutions  # type: ignore



@dataclass
class LabelSpec:
    name: str
    color: Tuple[int, int, int]
    source: str  # "pose"
    key: Tuple[str, ...]
    pose_indices: Optional[Iterable[int]] = None
    margin: float = 0.02  # applied for pose derived boxes


POSE_LABELS: List[LabelSpec] = [
    LabelSpec("head", (250, 128, 114), "pose", ("pose",), pose_indices=[0, 2, 5, 7, 8, 9, 10], margin=0.05),
    LabelSpec("hand_right", (65, 105, 225), "pose", ("pose",), pose_indices=[16, 18, 20, 22], margin=0.05),
    LabelSpec("hand_left", (60, 179, 113), "pose", ("pose",), pose_indices=[15, 17, 19, 21], margin=0.05),
    LabelSpec("torso", (255, 215, 0), "pose", ("pose",), pose_indices=[11, 12, 23, 24], margin=0.05),
    LabelSpec("arm_right", (255, 140, 0), "pose", ("pose",), pose_indices=[12, 14, 16, 18, 20], margin=0.04),
    LabelSpec("arm_left", (186, 85, 211), "pose", ("pose",), pose_indices=[11, 13, 15, 17, 19], margin=0.04),
    LabelSpec("leg_right", (72, 209, 204), "pose", ("pose",), pose_indices=[24, 26, 28, 30, 32], margin=0.05),
    LabelSpec("leg_left", (147, 112, 219), "pose", ("pose",), pose_indices=[23, 25, 27, 29, 31], margin=0.05),
]

BACKGROUND_COLOR = (160, 160, 160)


def _get_env_float(name: str, default: float) -> float:
    try:
        val = os.environ.get(name, "")
        if not val:
            return default
        return float(val)
    except Exception:
        return default

# Tunables (override via env vars if needed)
HEAD_MIN_W_FRAC = _get_env_float("PL_HEAD_MIN_W_FRAC", 0.12)
HEAD_MIN_H_FRAC = _get_env_float("PL_HEAD_MIN_H_FRAC", 0.15)
HEAD_INFLATE_X = _get_env_float("PL_HEAD_INFLATE_X", 1.15)
HEAD_INFLATE_Y = _get_env_float("PL_HEAD_INFLATE_Y", 1.40)
HEAD_UP_BIAS_FRAC = _get_env_float("PL_HEAD_UP_BIAS_FRAC", 0.35)  # shift up by 35% of box height
HEAD_TOP_STRETCH_FRAC = _get_env_float("PL_HEAD_TOP_STRETCH_FRAC", 0.35)  # extend only the top by 35% of box height
HEAD_TARGET_H_TO_TORSO_H = _get_env_float("PL_HEAD_TARGET_H_TO_TORSO_H", 0.65)  # ensure head height >= 65% of torso height

HAND_MIN_W_FRAC = _get_env_float("PL_HAND_MIN_W_FRAC", 0.08)
HAND_MIN_H_FRAC = _get_env_float("PL_HAND_MIN_H_FRAC", 0.10)
HAND_INFLATE_X = _get_env_float("PL_HAND_INFLATE_X", 1.20)
HAND_INFLATE_Y = _get_env_float("PL_HAND_INFLATE_Y", 1.20)
HAND_OUT_BIAS_FRAC = _get_env_float("PL_HAND_OUT_BIAS_FRAC", 0.06)  # push hands outward by 6% of box width

# Torso tuning: keep torso within shoulder span to avoid overhang
TORSO_X_PAD_NORM = _get_env_float("PL_TORSO_X_PAD_NORM", 0.02)      # normalized extra on both sides of shoulders
TORSO_TOP_MARGIN_NORM = _get_env_float("PL_TORSO_TOP_MARGIN_NORM", 0.02)
TORSO_BOTTOM_MARGIN_NORM = _get_env_float("PL_TORSO_BOTTOM_MARGIN_NORM", 0.03)
TORSO_MIN_POINTS = int(_get_env_float("PL_TORSO_MIN_POINTS", 120.0))





def write_colorized_ply(path: Path, points: np.ndarray, colors: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        fh.write("ply\nformat ascii 1.0\n")
        fh.write(f"element vertex {points.shape[0]}\n")
        fh.write("property float x\nproperty float y\nproperty float z\n")
        fh.write("property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n")
        for (x, y, z), (r, g, b) in zip(points, colors):
            fh.write(f"{x} {y} {z} {int(r)} {int(g)} {int(b)}\n")

def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float: return max(lo, min(hi, value))



def load_ply(path: Path) -> Tuple[np.ndarray, np.ndarray]:
    # Use plyfile to avoid pyvista dependency introduced by pyminiply's PointSet import
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





def clamp_bbox_to_pc(bbox: Dict[str, float], pc_bbox: Dict[str, float]) -> Dict[str, float]:
    return {
        "xmin": max(pc_bbox["xmin"], min(pc_bbox["xmax"], float(bbox["xmin"]))),
        "xmax": max(pc_bbox["xmin"], min(pc_bbox["xmax"], float(bbox["xmax"]))),
        "ymin": max(pc_bbox["ymin"], min(pc_bbox["ymax"], float(bbox["ymin"]))),
        "ymax": max(pc_bbox["ymin"], min(pc_bbox["ymax"], float(bbox["ymax"]))),
    }


def inflate_bbox(bbox: Dict[str, float], pc_bbox: Dict[str, float], scale_x: float = 1.0, scale_y: float = 1.0) -> Dict[str, float]:
    if not bbox:
        return bbox
    cx = (float(bbox["xmin"]) + float(bbox["xmax"])) * 0.5
    cy = (float(bbox["ymin"]) + float(bbox["ymax"])) * 0.5
    w = (float(bbox["xmax"]) - float(bbox["xmin"])) * scale_x
    h = (float(bbox["ymax"]) - float(bbox["ymin"])) * scale_y
    new_bbox = {
        "xmin": cx - 0.5 * w,
        "xmax": cx + 0.5 * w,
        "ymin": cy - 0.5 * h,
        "ymax": cy + 0.5 * h,
    }
    return clamp_bbox_to_pc(new_bbox, pc_bbox)


def offset_bbox(bbox: Dict[str, float], pc_bbox: Dict[str, float], dx: float = 0.0, dy: float = 0.0) -> Dict[str, float]:
    if not bbox:
        return bbox
    new_bbox = {
        "xmin": float(bbox["xmin"]) + dx,
        "xmax": float(bbox["xmax"]) + dx,
        "ymin": float(bbox["ymin"]) + dy,
        "ymax": float(bbox["ymax"]) + dy,
    }
    return clamp_bbox_to_pc(new_bbox, pc_bbox)


def stretch_top(bbox: Dict[str, float], pc_bbox: Dict[str, float], top_frac: float) -> Dict[str, float]:
    if not bbox or top_frac <= 0:
        return bbox
    h = (float(bbox["ymax"]) - float(bbox["ymin"]))
    dy = -top_frac * h
    new_ymin = float(bbox["ymin"]) + dy
    new_bbox = {
        "xmin": float(bbox["xmin"]),
        "xmax": float(bbox["xmax"]),
        "ymin": new_ymin,
        "ymax": float(bbox["ymax"]),
    }
    return clamp_bbox_to_pc(new_bbox, pc_bbox)


def ensure_min_size(bbox: Dict[str, float], pc_bbox: Dict[str, float], min_frac_w: float, min_frac_h: float) -> Dict[str, float]:
    pc_w = pc_bbox["xmax"] - pc_bbox["xmin"]
    pc_h = pc_bbox["ymax"] - pc_bbox["ymin"]
    w = float(bbox["xmax"]) - float(bbox["xmin"])
    h = float(bbox["ymax"]) - float(bbox["ymin"])
    need_w = max(w, min_frac_w * pc_w)
    need_h = max(h, min_frac_h * pc_h)
    cx = (float(bbox["xmin"]) + float(bbox["xmax"])) * 0.5
    cy = (float(bbox["ymin"]) + float(bbox["ymax"])) * 0.5
    xmin = cx - need_w * 0.5
    xmax = cx + need_w * 0.5
    ymin = cy - need_h * 0.5
    ymax = cy + need_h * 0.5
    return clamp_bbox_to_pc({"xmin": xmin, "xmax": xmax, "ymin": ymin, "ymax": ymax}, pc_bbox)





def refine_head_bbox(
    points: np.ndarray,
    head_xy: Optional[Dict[str, float]],
    torso_pose_xy: Optional[Dict[str, float]],
    pc_bbox: Dict[str, float],
) -> Optional[Dict[str, float]]:
    if not head_xy:
        return None
    head = ensure_min_size(head_xy, pc_bbox, HEAD_MIN_W_FRAC, HEAD_MIN_H_FRAC); head = refine_xy_bbox_with_points(points, head, pc_bbox, min_points=150)
    if not head:
        return None
    head = inflate_bbox(head, pc_bbox, scale_x=HEAD_INFLATE_X, scale_y=HEAD_INFLATE_Y)
    # Upward bias (smaller y is higher); then stretch top
    dy = -HEAD_UP_BIAS_FRAC * (head["ymax"] - head["ymin"])  # type: ignore[index]
    head = offset_bbox(head, pc_bbox, dx=0.0, dy=dy)
    head = stretch_top(head, pc_bbox, top_frac=HEAD_TOP_STRETCH_FRAC)
    # Ensure head height reaches target fraction of torso height by extending upwards
    if torso_pose_xy:
        torso_h = float(torso_pose_xy["ymax"] - torso_pose_xy["ymin"])  # type: ignore[index]
        head_h = float(head["ymax"] - head["ymin"])  # type: ignore[index]
        target_h = HEAD_TARGET_H_TO_TORSO_H * torso_h
        if head_h < target_h:
            head = offset_bbox(head, pc_bbox, dx=0.0, dy=-(target_h - head_h))
    return head


def refine_hand_bbox(
    points: np.ndarray,
    hand_xy: Optional[Dict[str, float]],
    torso_cx: float,
    pc_bbox: Dict[str, float],
) -> Optional[Dict[str, float]]:
    if not hand_xy:
        return None
    hand = ensure_min_size(hand_xy, pc_bbox, HAND_MIN_W_FRAC, HAND_MIN_H_FRAC); hand = refine_xy_bbox_with_points(points, hand, pc_bbox, min_points=80)
    if not hand:
        return None
    hand = inflate_bbox(hand, pc_bbox, scale_x=HAND_INFLATE_X, scale_y=HAND_INFLATE_Y)
    w = (hand["xmax"] - hand["xmin"])  # type: ignore[index]
    cx = 0.5 * (hand["xmin"] + hand["xmax"])  # type: ignore[index]
    dx = HAND_OUT_BIAS_FRAC * w * (1.0 if cx >= torso_cx else -1.0)
    return offset_bbox(hand, pc_bbox, dx=dx, dy=0.0)


def torso_bbox_normalized(results) -> Optional[Tuple[float, float, float, float]]:
    """Compute a torso box in normalized space from pose landmarks with small margins."""
    if not getattr(results, "pose_landmarks", None):
        return None
    try:
        mp_holistic = mp_solutions.holistic  # type: ignore
        LSH = results.pose_landmarks.landmark[mp_holistic.PoseLandmark.LEFT_SHOULDER]
        RSH = results.pose_landmarks.landmark[mp_holistic.PoseLandmark.RIGHT_SHOULDER]
        LHIP = results.pose_landmarks.landmark[mp_holistic.PoseLandmark.LEFT_HIP]
        RHIP = results.pose_landmarks.landmark[mp_holistic.PoseLandmark.RIGHT_HIP]
        xs = [float(LSH.x), float(RSH.x)]
        ys_top = [float(LSH.y), float(RSH.y)]
        ys_bot = [float(LHIP.y), float(RHIP.y)]
        xmin_n = max(0.0, min(xs) - TORSO_X_PAD_NORM)
        xmax_n = min(1.0, max(xs) + TORSO_X_PAD_NORM)
        ymin_n = max(0.0, min(ys_top) - TORSO_TOP_MARGIN_NORM)
        ymax_n = min(1.0, max(ys_bot) + TORSO_BOTTOM_MARGIN_NORM)
        return (xmin_n, xmax_n, ymin_n, ymax_n)
    except Exception:
        return None


def refine_xy_bbox_with_points(points: np.ndarray, bbox_xy: Dict[str, float], pc_bbox: Dict[str, float], min_points: int = 50) -> Optional[Dict[str, float]]:
    bbox_xy = clamp_bbox_to_pc(bbox_xy, pc_bbox); idxs = select_points(points, bbox_xy)
    if idxs.size < min_points: return None
    s = compute_stats(points[idxs]) or {}
    return {"xmin": float(bbox_xy["xmin"]), "xmax": float(bbox_xy["xmax"]), "ymin": float(bbox_xy["ymin"]), "ymax": float(bbox_xy["ymax"]), "zmin": s.get("zmin", float(pc_bbox["zmin"])), "zmax": s.get("zmax", float(pc_bbox["zmax"]))}


def bbox_from_pose(
    pose_landmarks: List[Dict[str, float]],
    indices: Iterable[int],
    pc_bbox: Dict[str, float],
    margin: float,
) -> Optional[Dict[str, float]]:
    coords = []
    for idx in indices:
        if idx < 0 or idx >= len(pose_landmarks):
            continue
        lm = pose_landmarks[idx]
        x, y = lm.get("x"), lm.get("y")
        if x is None or y is None:
            continue
        coords.append((clamp(float(x)), clamp(float(y))))
    if not coords:
        return None

    xs, ys = zip(*coords)
    xmin = clamp(min(xs) - margin)
    xmax = clamp(max(xs) + margin)
    ymin = clamp(min(ys) - margin)
    ymax = clamp(max(ys) + margin)

    px,py,pw,ph = pc_bbox["xmin"], pc_bbox["ymin"], pc_bbox["xmax"]-pc_bbox["xmin"], pc_bbox["ymax"]-pc_bbox["ymin"]
    return {"xmin": px + xmin*pw, "xmax": px + xmax*pw, "ymin": py + ymin*ph, "ymax": py + ymax*ph}


def select_points(points: np.ndarray, bbox: Dict[str, float]) -> np.ndarray:
    if not bbox:
        return np.array([], dtype=np.int64)
    mask = (
        (points[:, 0] >= bbox["xmin"]) &
        (points[:, 0] <= bbox["xmax"]) &
        (points[:, 1] >= bbox["ymin"]) &
        (points[:, 1] <= bbox["ymax"])
    )
    return np.nonzero(mask)[0]


def compute_stats(points: np.ndarray) -> Optional[Dict[str, float]]:
    if points.size == 0:
        return None
    return {
        "xmin": float(points[:, 0].min()),
        "xmax": float(points[:, 0].max()),
        "ymin": float(points[:, 1].min()),
        "ymax": float(points[:, 1].max()),
        "zmin": float(points[:, 2].min()),
        "zmax": float(points[:, 2].max()),
    }


def label_frame(
    frame_id: str,
    ply_path: Path,
    out_dir: Path,
    color_dir: Optional[Path],
    redis_out_stream: Optional[str] = None,
    redis_url: Optional[str] = None,
) -> bool:
    # Load PLY and compute bbox for mapping normalized coords
    points, colors = load_ply(ply_path)
    total_points = points.shape[0]

    # Compute pc bbox for mapping normalized coords to pc-space
    pc_bbox_defaults = {
        "xmin": float(points[:, 0].min()),
        "xmax": float(points[:, 0].max()),
        "ymin": float(points[:, 1].min()),
        "ymax": float(points[:, 1].max()),
        "zmin": float(points[:, 2].min()),
        "zmax": float(points[:, 2].max()),
    }

    # Derive landmarks and PII boxes using MediaPipe on a rendered preview (always)
    img = render_preview_rgb(points, colors, logger=LOGGER)
    if img is None:
        raise RuntimeError("preview rendering failed for labeling")
    mp_holistic = mp_solutions.holistic  # type: ignore
    holistic = mp_holistic.Holistic(static_image_mode=True, model_complexity=0)
    try:
        results = holistic.process(img)
    finally:
        holistic.close()

    # Collect pose landmarks list of dicts
    pose_landmarks_list: List[Dict[str, float]] = (
        [{"x": float(lm.x), "y": float(lm.y), "z": float(getattr(lm, "z", 0.0)), "visibility": float(getattr(lm, "visibility", 0.0))}
         for lm in results.pose_landmarks.landmark] if results.pose_landmarks else []
    )

    # Head bbox (prefer dedicated face mesh; else derive from subset of pose landmarks)
    def bbox_from_landmarks(lms) -> Optional[Tuple[float,float,float,float]]:
        if not lms:
            return None
        xs = [float(p.x) for p in lms]
        ys = [float(p.y) for p in lms]
        return (max(0.0, min(xs)), min(1.0, max(xs)), max(0.0, min(ys)), min(1.0, max(ys)))

    face_bbox_n = None
    if getattr(results, "face_landmarks", None):
        face_bbox_n = bbox_from_landmarks(results.face_landmarks.landmark)
    if face_bbox_n is None and results.pose_landmarks:
        idxs = [mp_holistic.PoseLandmark.NOSE,
                mp_holistic.PoseLandmark.LEFT_EYE,
                mp_holistic.PoseLandmark.RIGHT_EYE,
                mp_holistic.PoseLandmark.MOUTH_LEFT,
                mp_holistic.PoseLandmark.MOUTH_RIGHT]
        pts = [results.pose_landmarks.landmark[i] for i in idxs]
        face_bbox_n = bbox_from_landmarks(pts)

    def hand_bbox(hand_attr: str, fallback_idxs: List[int]) -> Optional[Tuple[float,float,float,float]]:
        lms = getattr(results, hand_attr)
        if lms:
            return bbox_from_landmarks(lms.landmark)
        if results.pose_landmarks:
            pts = [results.pose_landmarks.landmark[i] for i in fallback_idxs]
            return bbox_from_landmarks(pts)
        return None

    RH = [mp_holistic.PoseLandmark.RIGHT_WRIST,
          mp_holistic.PoseLandmark.RIGHT_INDEX,
          mp_holistic.PoseLandmark.RIGHT_THUMB]
    LH = [mp_holistic.PoseLandmark.LEFT_WRIST,
          mp_holistic.PoseLandmark.LEFT_INDEX,
          mp_holistic.PoseLandmark.LEFT_THUMB]

    rh_n = hand_bbox("right_hand_landmarks", RH)
    lh_n = hand_bbox("left_hand_landmarks", LH)

    # Torso (normalized) and mapping helper
    torso_n = torso_bbox_normalized(results)
    pc_bbox = pc_bbox_defaults
    def to_pc(bb_n: Optional[Tuple[float,float,float,float]]):
        if bb_n is None: return None
        xmin,xmax,ymin,ymax = bb_n; px,py,pw,ph = pc_bbox["xmin"], pc_bbox["ymin"], pc_bbox["xmax"]-pc_bbox["xmin"], pc_bbox["ymax"]-pc_bbox["ymin"]
        return {"xmin": px + xmin*pw, "xmax": px + xmax*pw, "ymin": py + ymin*ph, "ymax": py + ymax*ph}

    pose_landmarks = pose_landmarks_list

    labels_output: Dict[str, Dict] = {}
    assigned = np.zeros(total_points, dtype=bool)
    colored = colors.copy()

    def apply_label(spec: LabelSpec, bbox: Optional[Dict[str, float]]):
        if not bbox:
            labels_output[spec.name] = {"point_count": 0, "fraction": 0.0, "bbox": None}; return
        idxs = select_points(points, bbox); idxs = idxs[~assigned[idxs]]
        if idxs.size == 0:
            labels_output[spec.name] = {"point_count": 0, "fraction": 0.0, "bbox": None}; return
        assigned[idxs] = True
        stats = compute_stats(points[idxs])
        labels_output[spec.name] = {"point_count": int(idxs.size), "fraction": float(idxs.size / total_points), "bbox": stats}
        colored[idxs] = np.array(spec.color, dtype=np.uint8)

    # Build initial PII XY boxes from MediaPipe specialized signals, then enforce min sizes and refine with points
    head_pc = to_pc(face_bbox_n)
    rh_pc = to_pc(rh_n)
    lh_pc = to_pc(lh_n)
    # Estimate torso center in PC coords (for hand outward bias); fallback to overall center
    torso_pose_bbox = None
    if pose_landmarks_list:
        torso_pose_bbox = bbox_from_pose(
            pose_landmarks_list,
            [11, 12, 23, 24],  # shoulders + hips
            pc_bbox,
            margin=0.0,
        )
    if torso_pose_bbox:
        torso_cx = 0.5 * (torso_pose_bbox["xmin"] + torso_pose_bbox["xmax"])  # type: ignore[index]
    else:
        torso_cx = 0.5 * (pc_bbox["xmin"] + pc_bbox["xmax"])  # center of scene
    if head_pc:
        head_pc = refine_head_bbox(points, head_pc, torso_pose_bbox, pc_bbox)
    if rh_pc:
        rh_pc = refine_hand_bbox(points, rh_pc, torso_cx, pc_bbox)
    if lh_pc:
        lh_pc = refine_hand_bbox(points, lh_pc, torso_cx, pc_bbox)

    # Refine torso specialized bbox in PC space (optional) to avoid overhang
    torso_pc = to_pc(torso_n)
    if torso_pc:
        torso_pc = refine_xy_bbox_with_points(points, torso_pc, pc_bbox, min_points=TORSO_MIN_POINTS)

    # Pose-based labels
    for spec in POSE_LABELS:
        # Prefer specialized MediaPipe bboxes for head/hands; otherwise fall back to pose-only indices
        if spec.name == "head":
            bbox = head_pc if head_pc is not None else bbox_from_pose(pose_landmarks, spec.pose_indices or [], pc_bbox, spec.margin)
        elif spec.name == "hand_right":
            bbox = rh_pc if rh_pc is not None else bbox_from_pose(pose_landmarks, spec.pose_indices or [], pc_bbox, spec.margin)
        elif spec.name == "hand_left":
            bbox = lh_pc if lh_pc is not None else bbox_from_pose(pose_landmarks, spec.pose_indices or [], pc_bbox, spec.margin)
        elif spec.name == "torso" and torso_pc is not None:
            bbox = torso_pc
        else:
            bbox = bbox_from_pose(pose_landmarks, spec.pose_indices or [], pc_bbox, spec.margin)
        apply_label(spec, bbox)

    remaining = np.nonzero(~assigned)[0]
    labels_output["background"] = {
        "point_count": int(remaining.size),
        "fraction": float(remaining.size / total_points),
        "bbox": compute_stats(points[remaining]) if remaining.size else None,
    }
    colored[remaining] = np.array(BACKGROUND_COLOR, dtype=np.uint8)

    metrics = {
        "frame_id": frame_id,
        "total_points": int(total_points),
        "labeled_points": int(total_points - remaining.size),
        "labeled_fraction": float((total_points - remaining.size) / total_points),
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    labels_path = out_dir / f"labels-{frame_id}.json"
    with labels_path.with_suffix(".json.tmp").open("w", encoding="utf-8") as fh:
        json.dump({"frame_id": frame_id, "labels": labels_output, "metrics": metrics}, fh)
    labels_path.with_suffix(".json.tmp").replace(labels_path)

    if color_dir is not None:
        output_path = color_dir / f"labels-colored-{frame_id}.ply"
        write_colorized_ply(output_path, points, colored)
        # Best-effort preview PNG (atomic write inside helper)
        try:
            # Place preview at the OUT directory root so Results API can find it
            preview_path = out_dir / f"preview-labels-colored-{frame_id}.png"
            ok = generate_preview(points, colored, preview_path, logger=LOGGER)
            if ok:
                LOGGER.info("Generated labels-colored preview %s", preview_path.name)
        except Exception:  # pragma: no cover
            LOGGER.exception("Failed to generate labels-colored preview for %s", frame_id)


    LOGGER.info(
        "Processed %s | labeled %.1f%% (%d / %d)",
        frame_id,
        metrics["labeled_fraction"] * 100.0,
        metrics["labeled_points"],
        metrics["total_points"],
    )

    # keep input files; no deletion in streamlined flow

    # Publish event to Redis (optional)
    if redis_out_stream:
        r = get_client(redis_url)
        if r is not None:
            xadd_safe(
                r,
                redis_out_stream,
                {
                    "frame_id": frame_id,
                    "labels_path": labels_path.as_posix(),
                    "ply_path": ply_path.as_posix(),
                },
            )
    return True





def run_loop(args: argparse.Namespace) -> None:
    out_dir = Path(args.out_dir)
    color_dir = Path(args.colorized_dir) if args.colorized_dir else out_dir

    out_dir.mkdir(parents=True, exist_ok=True)
    color_dir.mkdir(parents=True, exist_ok=True)

    # Redis mode
    r = get_client(args.redis_url)
    if r is None:
        LOGGER.error("part-labeler: unable to connect to Redis at %s", args.redis_url)
        sys.exit(1)
    try:
        ensure_group(r, args.redis_in_stream, args.redis_group)
    except Exception:
        LOGGER.exception("part-labeler: failed to ensure Redis group")
        sys.exit(1)

    while True:
        entries = readgroup_blocking(
            r,
            args.redis_in_stream,
            args.redis_group,
            args.redis_consumer,
            count=8,
            block_ms=int(args.poll_interval * 1000),
        )
        for _, messages in entries or []:
            for msg_id, fields in messages:
                frame_id = fields.get("frame_id")
                if not frame_id:
                    xack_safe(r, args.redis_in_stream, args.redis_group, msg_id)
                    continue
                ply_field = fields.get("ply_path")
                if not ply_field:
                    xack_safe(r, args.redis_in_stream, args.redis_group, msg_id)
                    continue
                ply_path = Path(ply_field)
                try:
                    label_frame(
                        frame_id,
                        ply_path,
                        out_dir,
                        color_dir if args.write_colorized else None,
                        args.redis_out_stream,
                        args.redis_url,
                    )
                except Exception:
                    LOGGER.exception("Failed to label frame %s", frame_id)
                finally:
                    # ack regardless; upstream can resend if needed
                    xack_safe(r, args.redis_in_stream, args.redis_group, msg_id)
        continue


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Part labeler service")
    parser.add_argument("--out-dir", default="/segments", help="Directory where labels-*.json will be written")
    parser.add_argument("--colorized-dir", default="", help="Optional dir for colorized preview PLYs (defaults to --out-dir)")
    parser.add_argument("--write-colorized", action="store_true", help="Emit colorized PLY previews alongside JSON labels")
    parser.add_argument("--poll-interval", type=float, default=1.0, help="Polling interval in seconds while waiting for new frames")
    parser.add_argument("--log-level", choices=["debug","info","warning","error"], default="info")
    parser.add_argument("--redis-url", default=os.environ.get("REDIS_URL", ""), help="Redis URL (e.g., redis://host:6379/0)")
    parser.add_argument("--redis-out-stream", default=os.environ.get("REDIS_STREAM_PARTS_LABELED", "s_parts_labeled"), help="Stream to publish s_parts_labeled")
    parser.add_argument("--redis-in-stream", default=os.environ.get("REDIS_STREAM_FRAMES_CONVERTED", "s_frames_converted"), help="Stream to consume converted frames")
    parser.add_argument("--redis-group", default=os.environ.get("REDIS_GROUP_PART_LABELER", "g_part_labeler"), help="Consumer group name")
    parser.add_argument("--redis-consumer", default=os.environ.get("HOSTNAME", "part-labeler-1"), help="Consumer name")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper()),
        format="%(asctime)s.%(msecs)03d %(levelname)s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    LOGGER.info(
        "Starting part labeler (Redis-driven) | out=%s in-stream=%s out-stream=%s",
        args.out_dir,
        args.redis_in_stream,
        args.redis_out_stream,
    )
    run_loop(args)


if __name__ == "__main__":
    main()














