FROM python:3.11-slim

WORKDIR /app

# psycopg2 needs libpq headers at build time
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ .

# Most cloud platforms (Render, Cloud Run, Heroku, App Runner) inject $PORT.
# Default to 8000 so local `docker build && docker run` keeps working unchanged.
EXPOSE 8000

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
