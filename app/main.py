"""
Application de démonstration, volontairement minimale : le but de ce dépôt
n'est pas la logique métier de l'application, mais le pipeline CI/CD, la
conteneurisation, l'infrastructure et la sécurité qui l'entourent.

Elle expose :
- /health  : utilisée par les probes Kubernetes (liveness/readiness)
- /version : utile pour vérifier, après un déploiement, quelle version tourne
- /        : renvoie aussi le nom du pod (hostname) pour visualiser concrètement
             la répartition de charge entre plusieurs répliques
- /metrics : métriques Prometheus (requêtes comptées), scrappées par un
             éventuel Prometheus déployé sur le cluster
"""
import os

from fastapi import FastAPI
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response

APP_VERSION = os.environ.get("APP_VERSION", "dev")

app = FastAPI(title="DevSecOps Demo Service", version=APP_VERSION)

REQUEST_COUNTER = Counter("demo_requests_total", "Nombre total de requêtes reçues", ["path"])


@app.get("/")
def root():
    REQUEST_COUNTER.labels(path="/").inc()
    return {
        "message": "Bonjour depuis le pipeline DevSecOps !",
        "version": APP_VERSION,
        "pod_hostname": os.environ.get("HOSTNAME", "unknown"),
    }


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/version")
def version():
    return {"version": APP_VERSION}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
