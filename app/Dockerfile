# Build multi-stage : voir le rapport explicatif (partie Docker) pour le détail
# du raisonnement, déjà appliqué à l'identique dans le projet "API de paiement".
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
# UID/GID élevés et fixes (10001), volontairement éloignés de la plage des
# comptes système habituels (0-999) pour éviter toute collision avec un
# utilisateur du nœud hôte en cas d'évasion de conteneur.
RUN groupadd -g 10001 appuser && useradd -u 10001 -g appuser -r appuser

COPY --from=builder /install /usr/local
WORKDIR /app
COPY main.py .
RUN chown -R appuser:appuser /app
USER appuser

ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD curl -f http://localhost:8000/health || exit 1

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
