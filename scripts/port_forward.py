#!/usr/bin/env python3.12
"""Convenience: fetch a kubeconfig from Terraform outputs and port-forward
Grafana / Prometheus / Alertmanager / Tempo / OTel zpages in parallel.

Run after `terraform apply` from anywhere in the repo:

    python3.12 scripts/port_forward.py

Requires `kubectl` on PATH.
"""
from __future__ import annotations

import atexit
import json
import os
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TF_DIR = REPO / "terraform"

FORWARDS: list[tuple[str, str, str]] = [
    # (namespace, service, "local:remote")
    ("observability", "svc/kps-grafana",                                  "3000:80"),
    ("observability", "svc/kps-kube-prometheus-stack-prometheus",         "9090:9090"),
    ("observability", "svc/kps-kube-prometheus-stack-alertmanager",       "9093:9093"),
    ("observability", "svc/tempo",                                        "3200:3100"),
    ("opentelemetry", "svc/otel-collector",                               "55679:55679"),
]


def terraform_output(name: str) -> str:
    out = subprocess.run(
        ["terraform", f"-chdir={TF_DIR}", "output", "-raw", name],
        check=True, capture_output=True, text=True,
    )
    return out.stdout.strip()


def write_kubeconfig() -> Path:
    raw = terraform_output("kube_config")
    tmp = Path(tempfile.mkstemp(prefix="aks-kubeconfig-", suffix=".yaml")[1])
    tmp.write_text(raw)
    os.chmod(tmp, 0o600)
    atexit.register(lambda: tmp.unlink(missing_ok=True))
    return tmp


def grafana_password(kcfg: Path) -> str:
    env = {**os.environ, "KUBECONFIG": str(kcfg)}
    pw = subprocess.run(
        [
            "kubectl", "-n", "observability",
            "get", "secret", "kps-grafana",
            "-o", "jsonpath={.data.admin-password}",
        ],
        check=True, capture_output=True, text=True, env=env,
    ).stdout
    import base64
    return base64.b64decode(pw).decode()


def main() -> int:
    kcfg = write_kubeconfig()
    env = {**os.environ, "KUBECONFIG": str(kcfg)}

    pw = grafana_password(kcfg)
    print(f"Grafana       → http://localhost:3000   (admin / {pw})")
    print( "Prometheus    → http://localhost:9090")
    print( "Alertmanager  → http://localhost:9093")
    print( "Tempo         → http://localhost:3200")
    print( "OTel zpages   → http://localhost:55679")
    print()
    print("press Ctrl-C to stop forwarding")

    procs: list[subprocess.Popen] = []
    for ns, svc, ports in FORWARDS:
        p = subprocess.Popen(
            ["kubectl", "-n", ns, "port-forward", svc, ports],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        procs.append(p)

    def _bye(*_: object) -> None:
        for p in procs:
            p.terminate()
        sys.exit(0)

    signal.signal(signal.SIGINT, _bye)
    signal.signal(signal.SIGTERM, _bye)

    # Block until any forwarder dies.
    while True:
        for p in procs:
            if p.poll() is not None:
                _bye()
        signal.pause()


if __name__ == "__main__":
    raise SystemExit(main())
