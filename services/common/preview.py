"""Lightweight point-cloud preview rasterizer shared by services.

Features:
    * Orthographic XY projection (Z used only for depth shading)
    * ALWAYS flips Y so higher Y appears visually higher (consistent orientation)
    * Preserves aspect ratio: uses a uniform scale and centers the cloud, padding the shorter axis
    * Robust against NaNs / infs (drops invalid points)
    * Atomic write (temp file then rename)
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional, Tuple
import os
import numpy as np
from PIL import Image  # type: ignore


def render_preview_rgb(points: np.ndarray, colors: np.ndarray, *, size: Optional[int] = None, logger=None) -> Optional[np.ndarray]:
    """Rasterize a point cloud into an RGB image (numpy array).

    - Orthographic XY projection with uniform scaling and centering.
    - Y axis is mapped directly (increasing Y appears higher in the image).
    - Returns an RGB ndarray of shape (size, size, 3) or None on failure.
    """
    if size is None:
        try:
            size = int(os.environ.get("PREVIEW_SIZE", "640"))
        except ValueError:
            size = 640
    if points.size == 0:
        if logger:
            logger.warning("No points for preview image")
        return None
    pts = points.astype(float)
    cols = colors.astype("uint8") if colors.dtype != 'uint8' else colors
    # Remove rows with NaNs / infs
    mask = np.isfinite(pts).all(axis=1)
    if not mask.all():
        dropped = (~mask).sum()
        pts = pts[mask]
        cols = cols[mask]
        if logger:
            logger.debug("Dropped %d invalid points before preview", dropped)
    if pts.shape[0] == 0:
        if logger:
            logger.warning("All points invalid for preview image")
        return None
    xs, ys, zs = pts[:,0], pts[:,1], pts[:,2]
    xmin,xmax = float(xs.min()), float(xs.max()); xr = xmax - xmin
    ymin,ymax = float(ys.min()), float(ys.max()); yr = ymax - ymin
    if xr <= 0 and yr <= 0:
        if logger:
            logger.warning("Degenerate bounds for preview image")
        return None
    span = max(xr, yr, 1e-9)
    # Centering box (use uniform span to preserve aspect)
    cx = 0.5 * (xmin + xmax)
    cy = 0.5 * (ymin + ymax)
    half = 0.5 * span
    # Normalized coordinates in [0,1] (may slightly exceed due to centering when xr!=yr; clip)
    nx = (xs - (cx - half)) / span
    ny = (ys - (cy - half)) / span
    nx = np.clip(nx, 0.0, 1.0)
    ny = np.clip(ny, 0.0, 1.0)
    px = (nx * (size - 1)).astype(int)
    # Map Y directly. Larger Y plots higher visually.
    py = (ny * (size - 1)).astype(int)
    # Depth shading
    zmin,zmax = float(zs.min()), float(zs.max()); zr = zmax - zmin or 1.0
    shade = (0.4 + 0.6 * (1.0 - (zs - zmin)/zr))[:,None]
    shaded = np.clip(cols.astype(float)*shade,0,255).astype("uint8")
    # Build RGB image
    img = np.zeros((size,size,3), dtype="uint8") + 30
    img[py, px] = shaded  # RGB
    return img


def generate_preview(points: np.ndarray, colors: np.ndarray, out_path: Path, *, logger=None, size: Optional[int] = None) -> bool:
    img = render_preview_rgb(points, colors, size=size, logger=logger)
    if img is None:
        return False
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_name(out_path.stem + '.tmp' + out_path.suffix)
    try:
        Image.fromarray(img).save(tmp.as_posix(), format="PNG")  # RGB
    except Exception as e:  # pragma: no cover
        if logger:
            logger.error("Failed to write preview %s: %s", out_path.name, e)
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass
        return False

    try:
        tmp.replace(out_path)
    except Exception as e:  # pragma: no cover
        if logger:
            logger.error("Failed to finalize preview %s: %s", out_path.name, e)
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass
        return False

    if logger:
        logger.info("Generated preview %s", out_path.name)
    return True
