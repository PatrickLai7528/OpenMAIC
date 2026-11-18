#!/usr/bin/env bash
# Apply OpenMAIC manifests; pass secrets/image via env (or --env-file).
#
# Required:
#   DATABASE_URL      e.g. postgres://USER:PASS@HOST:5432/DB
#   OPENAI_API_KEY    Volcengine Ark API key (ark-...)
#   IMAGE             e.g. ghcr.io/you/openmaic:agent-runtime
#   GHCR_USERNAME     GitHub username (for private GHCR pull)
#   GHCR_TOKEN        GitHub PAT with read:packages (or write:packages)
#
# Optional:
#   GHCR_EMAIL                default empty (docker-registry secret)
#   OPENAI_BASE_URL           default = https://ark.cn-beijing.volces.com/api/v3
#   OPENAI_MODELS             default = doubao-seed-2-1-pro-260628
#   MINIMAX_API_KEY           only for MiniMax chat/TTS; not used as the LLM default
#   MINIMAX_BASE_URL          default = https://api.minimaxi.com/anthropic/v1
#   MINIMAX_MODELS            default = MiniMax-M2.7-highspeed
#   TTS_MINIMAX_API_KEY       default = MINIMAX_API_KEY (server-side narration TTS
#                           for PRO/agent runtime; without it generate_tts reports
#                           "no enabled server TTS capability" and pages stay silent)
#   TTS_MINIMAX_BASE_URL      default = https://api.minimaxi.com
#   ACCESS_CODE               default empty
#   NAMESPACE                 default = open-maic
#   APPLY_INGRESS             default = 1 (set 0 to skip Ingress)
#   GHCR_SERVER               default = ghcr.io
#   KUBECTL_VALIDATE          default = false
#                             School clusters sometimes return broken OpenAPI
#                             (HTML/proxy). Set true to re-enable client validation.
#
# Examples:
#   ./apply.sh --env-file ./deploy.env   # vars stay inside this process only
#   set -a && source ./deploy.env && set +a && ./apply.sh

set -euo pipefail

# --env-file: load secrets from a file without exporting them into the
# caller's interactive shell — they live only in this process and its
# children (kubectl). Resolve to an absolute path before cd below.
ENV_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file) ENV_FILE="${2:?--env-file needs a path}"; shift 2 ;;
    --env-file=*) ENV_FILE="${1#*=}"; shift ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ -n "$ENV_FILE" ]]; then
  [[ "$ENV_FILE" = /* ]] || ENV_FILE="$(pwd)/${ENV_FILE#./}"
  [[ -f "$ENV_FILE" ]] || { echo "ERROR: env file not found: $ENV_FILE" >&2; exit 1; }
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

NAMESPACE="${NAMESPACE:-open-maic}"
APPLY_INGRESS="${APPLY_INGRESS:-1}"
GHCR_SERVER="${GHCR_SERVER:-ghcr.io}"
GHCR_EMAIL="${GHCR_EMAIL:-}"
KUBECTL_VALIDATE="${KUBECTL_VALIDATE:-false}"

: "${DATABASE_URL:?Set DATABASE_URL (postgres://user:pass@host:5432/db)}"
: "${OPENAI_API_KEY:?Set OPENAI_API_KEY (Volcengine Ark key)}"
: "${IMAGE:?Set IMAGE (registry/name:tag)}"
: "${GHCR_USERNAME:?Set GHCR_USERNAME (GitHub username)}"
: "${GHCR_TOKEN:?Set GHCR_TOKEN (PAT with read:packages)}"

OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://ark.cn-beijing.volces.com/api/v3}"
OPENAI_MODELS="${OPENAI_MODELS:-doubao-seed-2-1-pro-260628}"
MINIMAX_API_KEY="${MINIMAX_API_KEY:-}"
MINIMAX_BASE_URL="${MINIMAX_BASE_URL:-https://api.minimaxi.com/anthropic/v1}"
MINIMAX_MODELS="${MINIMAX_MODELS:-MiniMax-M2.7-highspeed}"
TTS_MINIMAX_API_KEY="${TTS_MINIMAX_API_KEY:-$MINIMAX_API_KEY}"
TTS_MINIMAX_BASE_URL="${TTS_MINIMAX_BASE_URL:-https://api.minimaxi.com}"
ACCESS_CODE="${ACCESS_CODE:-}"

kapply() {
  kubectl apply --validate="${KUBECTL_VALIDATE}" "$@"
}

echo "==> preflight: API server must speak Kubernetes JSON (not HTML)"
if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
  echo "ERROR: cannot reach a healthy Kubernetes API."
  echo "  current context: $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "  server: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo unknown)"
  echo "  Tip: kubectl config get-contexts"
  echo "       kubectl config use-context <school-cluster>"
  echo "  If the server URL opens in a browser as a web UI, you are pointing at the wrong endpoint."
  exit 1
fi

echo "==> namespace ${NAMESPACE}"
kapply -f 00-namespace.yaml

echo "==> secret registry-cred (GHCR pull)"
kubectl -n "${NAMESPACE}" create secret docker-registry registry-cred \
  --docker-server="${GHCR_SERVER}" \
  --docker-username="${GHCR_USERNAME}" \
  --docker-password="${GHCR_TOKEN}" \
  --docker-email="${GHCR_EMAIL}" \
  --dry-run=client -o yaml | kapply -f -

echo "==> secret openmaic-secrets (from env)"
kubectl -n "${NAMESPACE}" create secret generic openmaic-secrets \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=MINIMAX_API_KEY="${MINIMAX_API_KEY}" \
  --from-literal=MINIMAX_BASE_URL="${MINIMAX_BASE_URL}" \
  --from-literal=MINIMAX_MODELS="${MINIMAX_MODELS}" \
  --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY}" \
  --from-literal=OPENAI_BASE_URL="${OPENAI_BASE_URL}" \
  --from-literal=OPENAI_MODELS="${OPENAI_MODELS}" \
  --from-literal=TTS_MINIMAX_API_KEY="${TTS_MINIMAX_API_KEY}" \
  --from-literal=TTS_MINIMAX_BASE_URL="${TTS_MINIMAX_BASE_URL}" \
  --from-literal=ACCESS_CODE="${ACCESS_CODE}" \
  --dry-run=client -o yaml | kapply -f -

echo "==> configmap / pvc / deployment / service"
kapply -f 02-configmap.yaml
kapply -f 06-pvc.yaml
kapply -f 03-deployment.yaml
kapply -f 04-service.yaml

if [[ "${APPLY_INGRESS}" == "1" ]]; then
  echo "==> ingress"
  kapply -f 05-ingress.yaml
else
  echo "==> skip ingress (APPLY_INGRESS=${APPLY_INGRESS})"
fi

echo "==> set image -> ${IMAGE}"
kubectl -n "${NAMESPACE}" set image deployment/openmaic "openmaic=${IMAGE}"
# envFrom secrets are snapshotted at pod start; always bounce so new keys apply
kubectl -n "${NAMESPACE}" rollout restart deployment/openmaic
kubectl -n "${NAMESPACE}" rollout status deployment/openmaic --timeout=180s

echo "==> done"
kubectl -n "${NAMESPACE}" get pods,svc -l app.kubernetes.io/name=openmaic
