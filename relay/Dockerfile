# Rhythia-reimagined relay: one Python file, standard library only.
FROM python:3.12-alpine
WORKDIR /app
COPY rr_relay.py .
RUN adduser -D -H relay
USER relay
ENV RR_RELAY_BIND=0.0.0.0 \
    RR_RELAY_PORT=8080 \
    PYTHONUNBUFFERED=1
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2).status == 200 else 1)"
STOPSIGNAL SIGTERM
CMD ["python", "rr_relay.py"]
