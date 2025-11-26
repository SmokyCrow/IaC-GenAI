FROM python:3.12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN mkdir -p /semantic-segmenter

WORKDIR /semantic-segmenter

RUN apt update && \
    apt install -y libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

COPY ./requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt

RUN mkdir -p /sub-pc-frames && \
    mkdir -p /pc-frames && \
    mkdir -p /segments

RUN apt update && \
    apt install -y draco && \
    rm -rf /var/lib/apt/lists/*

COPY ./services ./services
CMD ["bash", "-lc", "python3 services/convert_service/convert-ply --in-dir /sub-pc-frames --out-dir /pc-frames --preview-out-dir /segments --delete-source --log-level info & python3 services/part_labeler/part_labeler.py --log-level info --out-dir /segments --colorized-dir /segments/labels --write-colorized"]
