"""Frontend service — Flask. Talks to the backend over HTTP.

The OpenTelemetry Operator auto-injects instrumentation, so this code stays
free of any vendor SDK boilerplate. Tracing, metrics and log correlation
happen via the sidecar init container.
"""
import os
import random
import time
import logging

import requests
from flask import Flask, jsonify, request

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("frontend")

app = Flask(__name__)
BACKEND_URL = os.environ.get("BACKEND_URL", "http://backend.demo-apps.svc:8080")


@app.get("/healthz")
def healthz():
    return "ok", 200


@app.get("/api/order")
def order():
    user = request.args.get("user", "anonymous")
    log.info("creating order for user=%s", user)
    try:
        r = requests.get(f"{BACKEND_URL}/inventory", timeout=2)
        r.raise_for_status()
        inventory = r.json()
    except Exception as exc:
        log.exception("backend call failed")
        return jsonify({"error": str(exc)}), 502

    # Simulate variable latency so dashboards aren't flat.
    time.sleep(random.uniform(0.02, 0.4))

    if random.random() < 0.03:
        return jsonify({"error": "synthetic 500 for SLO testing"}), 500

    return jsonify({
        "user": user,
        "items": random.sample(inventory["items"], k=min(3, len(inventory["items"]))),
        "total": round(random.uniform(10, 200), 2),
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
