FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY services/ingest_api/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY services/ingest_api/ingest_api.py ./ingest_api.py

ENV INGEST_OUT_DIR=/sub-pc-frames

EXPOSE 8080

CMD ["uvicorn", "ingest_api:app", "--host", "0.0.0.0", "--port", "8080"]

