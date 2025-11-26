# Part Labeler Service

Consumes converted PLY frames and produces per-part labels and optionally colorized previews.

## Inputs
- `/pc-frames/<frame>.ply` – decoded point clouds from the convert service; frame events arrive via Redis stream `s_frames_converted`.

## Outputs
- `/segments/labels-<frame>.json` – point counts, bounding boxes, and coverage metrics for face, hands, arms, legs, torso, and background.
- `/segments/labels/labels-colored-<frame>.ply` – colorized PLY preview (enable via env var or CLI flag if supported).


Local run (example):
```bash
python services/part_labeler/part_labeler.py
```
The service is environment-driven; see deployment manifests for configurable variables.
