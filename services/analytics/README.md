# Analytics Service

Computes per-frame analytics from the part labeler outputs: totals, per-part coverage, densities, basic QoS flags, and simple motion between consecutive frames. Results are written as `metrics-<frame>.json` and an event is published to Redis Streams. This service is Redis-only (no filesystem scanning or fallback modes).

## Inputs
- `/segments/labels-<frame>.json` – produced by the Part Labeler, contains per-part counts, fractions, and bounding boxes.

## Outputs
- `/segments/metrics-<frame>.json` – aggregated analytics document:
  - `totals` – `total_points`, `labeled_points`, `labeled_fraction`.
  - `per_part` – for each part: `point_count`, `fraction`, `bbox`, `center`, `volume`, `density` (when z-range exists).
  - `flags` – `low_coverage`, `head_missing`, `hands_missing`.
  - `motion` – per-part Euclidean delta of centers vs previous frame (if previous metrics available).
  

## Redis Streams
- Consumes: `s_parts_labeled` – events from Part Labeler.
- Publishes: `s_analytics_done` – includes `frame_id` and `metrics_path`.

## Run (Redis)
```bash
export REDIS_URL="redis://localhost:6379/0"
export REDIS_STREAM_PARTS_LABELED="s_parts_labeled"
export REDIS_STREAM_ANALYTICS_DONE="s_analytics_done"
python services/analytics/analytics.py
```

## Notes
- Files are written atomically (`.tmp` + rename) and the service is idempotent (skips if the final metrics file exists).
- A minimum file age guards against races with writers (`--min-age`, defaults to `0.5s`).
- `--low-coverage-threshold` sets the threshold for the `low_coverage` flag (default `0.2`).