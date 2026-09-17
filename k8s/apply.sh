#!/usr/bin/env bash
# Apply OpenMAIC manifests; pass secrets/image via env (or --env-file).
#
# Required:
#   DATABASE_URL   e.g. postgres://USER:PASS@HOST:5432/DB
#   MINIMAX_API_KEY
#   IMAGE          e.g. ghcr.io/you/openmaic:agent-runtime
#
# Optional:
#   OPENAI_API_KEY          default = MINIMAX_API_KEY (OpenAI-compatible MiniMax)
#   OPENAI_BASE_URL         default = https://api.minimaxi.com/v1
#   OPENAI_MODELS           default = MiniMax-M2.7-highspeed
#   MINIMAX_BASE_URL        default = https://api.minimaxi.com/anthropic/v1
#   MINIMAX_MODELS          default = MiniMax-M2.7-highspeed
#   PERSISTENCE_DEV_TOKEN   default = openmaic-school-dev
#   ACCESS_CODE             default empty
#   NAMESPACE               default = ky-super-openamic
#   APPLY_INGRESS           default = 1 (set 0 to skip Ingress)
#
# Examples:
#   export DATABASE_URL='postgres://open_maic:CHANGE_ME@YOUR_PG_HOST:5432/open_maic'
#   export MINIMAX_API_KEY='sk-...'
#   export IMAGE='ghcr.io/you/openmaic:agent-runtime'
#   ./apply.sh
#
#   set -a && source ./deploy.env && set +a && ./apply.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

NAMESPACE="${NAMESPACE:-ky-super-openamic}"
APPLY_INGRESS="${APPLY_INGRESS:-1}"

: "${DATABASE_URL:?Set DATABASE_URL (postgres://user:pass@host:5432/db)}"
: "${MINIMAX_API_KEY:?Set MINIMAX_API_KEY}"
: "${IMAGE:?Set IMAGE (registry/name:tag)}"

OPENAI_API_KEY="${OPENAI_API_KEY:-$MINIMAX_API_KEY}"
OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.minimaxi.com/v1}"
OPENAI_MODELS="${OPENAI_MODELS:-MiniMax-M2.7-highspeed}"
MINIMAX_BASE_URL="${MINIMAX_BASE_URL:-https://api.minimaxi.com/anthropic/v1}"
MINIMAX_MODELS="${MINIMAX_MODELS:-MiniMax-M2.7-highspeed}"
PERSISTENCE_DEV_TOKEN="${PERSISTENCE_DEV_TOKEN:-openmaic-school-dev}"
PERSISTENCE_ALLOW_INSECURE_DEV_AUTH="${PERSISTENCE_ALLOW_INSECURE_DEV_AUTH:-true}"
ACCESS_CODE="${ACCESS_CODE:-}"

echo "==> namespace ${NAMESPACE}"
kubectl apply -f 00-namespace.yaml

echo "==> secret openmaic-secrets (from env)"
kubectl -n "${NAMESPACE}" create secret generic openmaic-secrets \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=MINIMAX_API_KEY="${MINIMAX_API_KEY}" \
  --from-literal=MINIMAX_BASE_URL="${MINIMAX_BASE_URL}" \
  --from-literal=MINIMAX_MODELS="${MINIMAX_MODELS}" \
  --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY}" \
  --from-literal=OPENAI_BASE_URL="${OPENAI_BASE_URL}" \
  --from-literal=OPENAI_MODELS="${OPENAI_MODELS}" \
  --from-literal=PERSISTENCE_DEV_TOKEN="${PERSISTENCE_DEV_TOKEN}" \
  --from-literal=PERSISTENCE_ALLOW_INSECURE_DEV_AUTH="${PERSISTENCE_ALLOW_INSECURE_DEV_AUTH}" \
  --from-literal=ACCESS_CODE="${ACCESS_CODE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> configmap / deployment / service"
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-deployment.yaml
kubectl apply -f 04-service.yaml

if [[ "${APPLY_INGRESS}" == "1" ]]; then
  echo "==> ingress"
  kubectl apply -f 05-ingress.yaml
else
  echo "==> skip ingress (APPLY_INGRESS=${APPLY_INGRESS})"
fi

echo "==> set image -> ${IMAGE}"
kubectl -n "${NAMESPACE}" set image deployment/openmaic "openmaic=${IMAGE}"
kubectl -n "${NAMESPACE}" rollout status deployment/openmaic --timeout=180s

echo "==> done"
kubectl -n "${NAMESPACE}" get pods,svc -l app.kubernetes.io/name=openmaic
