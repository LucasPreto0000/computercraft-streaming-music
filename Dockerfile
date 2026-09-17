FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN python -m pip install --no-cache-dir --upgrade yt-dlp

WORKDIR /app
COPY backend/server.py /app/server.py

EXPOSE 10000
CMD ["python", "/app/server.py"]
