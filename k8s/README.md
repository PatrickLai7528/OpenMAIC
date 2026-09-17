# OpenMAIC — Kubernetes 佈署（namespace: `ky-super-openamic`）

密鑰與映像**不要**寫死在 Git YAML。用環境變數（或 `deploy.env`）在套用時傳入。

| 變數 | 必填 | 說明 |
|------|------|------|
| `DATABASE_URL` | ✅ | 例：`postgres://open_maic:CHANGE_ME@YOUR_PG_HOST:5432/open_maic` |
| `MINIMAX_API_KEY` | ✅ | MiniMax API Key |
| `IMAGE` | ✅ | 例：`ghcr.io/<owner>/<repo>:agent-runtime`（由 GitHub Actions `Docker GHCR` workflow 推送） |
| `GHCR_USERNAME` | ✅ | GitHub 用戶名（拉 Private GHCR 映像） |
| `GHCR_TOKEN` | ✅ | GitHub PAT，至少勾選 `read:packages` |
| `GHCR_EMAIL` | 可選 | docker-registry secret 用，可空 |
| `OPENAI_API_KEY` | 可選 | 預設等於 `MINIMAX_API_KEY`（OpenAI 相容端點） |
| `OPENAI_BASE_URL` / `OPENAI_MODELS` | 可選 | 預設 MiniMax OpenAI 相容設定 |
| `APPLY_INGRESS` | 可選 | 預設 `1`；設 `0` 跳過 Ingress |

Agent Runtime 需要 **直連** Postgres（`LISTEN`/`NOTIFY`），勿用 transaction-mode pooler。

---

## 推薦：`./apply.sh`（參數／ENV 傳入）

```bash
cd OpenMAIC/k8s
cp deploy.env.example deploy.env   # 編輯填入真實值（已 gitignore）

set -a && source ./deploy.env && set +a
chmod +x ./apply.sh
./apply.sh
```

或一行不落地檔案：

```bash
DATABASE_URL='postgres://open_maic:CHANGE_ME@YOUR_PG_HOST:5432/open_maic' \
MINIMAX_API_KEY='sk-...' \
IMAGE='ghcr.io/YOUR_USER/openmaic:agent-runtime' \
GHCR_USERNAME='YOUR_GITHUB_USERNAME' \
GHCR_TOKEN='ghp_...' \
./apply.sh
```

腳本會：

1. `kubectl apply` Namespace / ConfigMap / Deployment / Service（可選 Ingress）
2. 用 env 建立／更新 Secret `registry-cred`（GHCR pull）與 `openmaic-secrets`
3. `kubectl set image deployment/openmaic openmaic=$IMAGE`

---

## 只用 kubectl（等價手動）

```bash
export NAMESPACE=ky-super-openamic
export DATABASE_URL='postgres://open_maic:CHANGE_ME@YOUR_PG_HOST:5432/open_maic'
export MINIMAX_API_KEY='sk-...'
export IMAGE='ghcr.io/YOUR_USER/openmaic:agent-runtime'
export GHCR_USERNAME='YOUR_GITHUB_USERNAME'
export GHCR_TOKEN='ghp_...'

kubectl apply -f 00-namespace.yaml

kubectl -n "$NAMESPACE" create secret docker-registry registry-cred \
  --docker-server=ghcr.io \
  --docker-username="$GHCR_USERNAME" \
  --docker-password="$GHCR_TOKEN" \
  --docker-email="${GHCR_EMAIL:-}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create secret generic openmaic-secrets \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=MINIMAX_API_KEY="$MINIMAX_API_KEY" \
  --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY:-$MINIMAX_API_KEY}" \
  --from-literal=OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.minimaxi.com/v1}" \
  --from-literal=OPENAI_MODELS="${OPENAI_MODELS:-MiniMax-M2.7-highspeed}" \
  --from-literal=MINIMAX_BASE_URL="${MINIMAX_BASE_URL:-https://api.minimaxi.com/anthropic/v1}" \
  --from-literal=MINIMAX_MODELS="${MINIMAX_MODELS:-MiniMax-M2.7-highspeed}" \
  --from-literal=PERSISTENCE_DEV_TOKEN="${PERSISTENCE_DEV_TOKEN:-openmaic-school-dev}" \
  --from-literal=PERSISTENCE_ALLOW_INSECURE_DEV_AUTH=true \
  --from-literal=ACCESS_CODE="${ACCESS_CODE:-}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f 02-configmap.yaml -f 03-deployment.yaml -f 04-service.yaml
kubectl -n "$NAMESPACE" set image deployment/openmaic "openmaic=${IMAGE}"
```

之後只換映像或密鑰：

```bash
# 換 image
kubectl -n ky-super-openamic set image deployment/openmaic openmaic="$IMAGE"

# 更新 Secret 後重啟 Pod
kubectl -n ky-super-openamic create secret generic openmaic-secrets \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=MINIMAX_API_KEY="$MINIMAX_API_KEY" \
  --from-literal=OPENAI_API_KEY="${OPENAI_API_KEY:-$MINIMAX_API_KEY}" \
  --from-literal=OPENAI_BASE_URL=https://api.minimaxi.com/v1 \
  --from-literal=OPENAI_MODELS=MiniMax-M2.7-highspeed \
  --from-literal=MINIMAX_BASE_URL=https://api.minimaxi.com/anthropic/v1 \
  --from-literal=MINIMAX_MODELS=MiniMax-M2.7-highspeed \
  --from-literal=PERSISTENCE_DEV_TOKEN=openmaic-school-dev \
  --from-literal=PERSISTENCE_ALLOW_INSECURE_DEV_AUTH=true \
  --from-literal=ACCESS_CODE= \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ky-super-openamic rollout restart deployment/openmaic
```

---

## 佈署前檢查

1. 集群能否訪問 Postgres 主機（`DATABASE_URL` 裡的 host:port）
2. 映像已含 Workbench build-arg；Private GHCR 時在 `deploy.env` 填好 `GHCR_USERNAME` / `GHCR_TOKEN`（`apply.sh` 會建 `registry-cred`）
3. （可選）修改 Ingress host

---

## 驗證

```bash
kubectl -n ky-super-openamic get pods,svc,ingress
kubectl -n ky-super-openamic logs -l app.kubernetes.io/name=openmaic --tail=80
kubectl -n ky-super-openamic port-forward svc/openmaic 3001:80
```

---

## 檔案一覽

| 檔案 | 內容 |
|------|------|
| `apply.sh` | 用 ENV 套用 Secret + Image |
| `deploy.env.example` | 參數範本（複製為 `deploy.env`） |
| `00-namespace.yaml` | Namespace |
| `01-secret.yaml` | 僅說明；真實 Secret 由 apply 建立 |
| `02-configmap.yaml` | Runtime 開關、`MODEL_ROUTES` |
| `03-deployment.yaml` | Deployment（image 由 apply 覆寫） |
| `04-service.yaml` / `05-ingress.yaml` | Service / Ingress |
| `kustomization.yaml` | 可選；Secret 不在此清單 |

---

## 注意

- `NEXT_PUBLIC_*` 是映像建置期參數，不能只靠 K8s env 打開 Workbench。
- 勿把 `deploy.env` 或含真實密碼的 Secret YAML 推進公開 Git。
- 完整步驟見同目錄 **[DEPLOY.md](./DEPLOY.md)**。
