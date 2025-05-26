FROM python:3.9-slim

WORKDIR /app

COPY ./metrics/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY ./metrics /app/metrics
COPY ./config /app/config

EXPOSE 8000

CMD ["python", "/app/metrics/exporter.py"] 