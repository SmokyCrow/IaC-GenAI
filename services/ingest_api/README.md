Ingest API
==========

Minimal FastAPI service to receive Draco-encoded tiles and store them
for the convert service. It supports both multipart uploads and raw
octet-stream bodies.

Endpoints
- POST /frames/{frame_id}
  - Stores as 0-{frame_id}.drc by default.
  - Optional header: X-Layer-Id to override the layer (integer).
- POST /tiles/{layer}/{frame_id}
  - Stores as {layer}-{frame_id}.drc.
- GET /healthz
  - Liveness/readiness probe.

Storage
- Output directory is taken from env var INGEST_OUT_DIR.
- Default: /sub-pc-frames (matches the convert service mount).

Run locally
- pip install -r services/ingest_api/requirements.txt
- uvicorn services.ingest_api.ingest_api:app --host 0.0.0.0 --port 8080

Example uploads

Raw body (single file → 0-00001.drc):
  curl -X POST --data-binary @0-00001.drc \
       http://localhost:8080/frames/00001

Multipart (tile → 2-00001.drc):
  curl -X POST -F file=@tile.drc \
       http://localhost:8080/tiles/2/00001

