# OpenMAIC → Kubernetes 佈署指南

Namespace：**`ky-super-openamic`**  
開發分支（會觸發建 image）：**`feat/patricklai7528-dev`**  
映像倉庫：**GHCR** `ghcr.io/<owner>/<repo>`（小寫）

本文件說明從「推程式碼」到「集群跑起來」的完整流程。  
密鑰用環境變數傳入，**不要**寫進 Git。本目錄 `.gitignore` 已忽略 `deploy.env`。

---

## 總覽

```text
feat/patricklai7528-dev  push
        │
        ▼
GitHub Actions (docker-ghcr.yml)
        │  build + push
        ▼
ghcr.io/<owner>/<repo>:agent-runtime | :latest | :sha-xxxx
        │
        ▼
kubectl / ./apply.sh  →  ky-super-openamic
        │
        ▼
Pods 連外掛 Postgres（DATABASE_URL）
```

---

## 0. 前置條件

| 項目 | 說明 |
|------|------|
| `kubectl` | 已連上校內集群，可操作 `ky-super-openamic` |
| Postgres | 集群 Pod 能直連（支援 `LISTEN`/`NOTIFY`，勿用 transaction pooler） |
| GHCR 映像 | 已 push `feat/patricklai7528-dev` 並等 Actions 成功 |
| MiniMax Key | 有可用 API Key |
| Repo 權限 | Actions → Workflow permissions → **Read and write**（才能推 Package） |

---

## 1. 產出映像（CI）

```bash
git checkout feat/patricklai7528-dev
# …改完程式…
git push -u origin feat/patricklai7528-dev
```

到 GitHub → **Actions** → **Docker GHCR**，等成功。  
到 **Packages** 確認映像，例如：

```text
ghcr.io/<你的帳號小寫>/<repo小寫>:agent-runtime
ghcr.io/<你的帳號小寫>/<repo小寫>:sha-<短SHA>
```

若 Package 是 Private，K8s 需要拉映像密鑰（見 §3）。

---

## 2. 準備本機密鑰檔（不進 Git）

```bash
cd k8s
cp deploy.env.example deploy.env
```

編輯 `deploy.env`（此檔被 `k8s/.gitignore` 忽略）：

```bash
NAMESPACE=ky-super-openamic

DATABASE_URL=postgres://USER:PASSWORD@PG_HOST:5432/DB_NAME
MINIMAX_API_KEY=sk-你的真實key
IMAGE=ghcr.io/<owner>/<repo>:agent-runtime
```

| 變數 | 必填 | 說明 |
|------|------|------|
| `DATABASE_URL` | ✅ | Postgres 連線字串 |
| `MINIMAX_API_KEY` | ✅ | MiniMax API Key（`OPENAI_API_KEY` 預設跟它相同） |
| `IMAGE` | ✅ | GHCR 映像 tag（建議用 `sha-…` 鎖定版本） |
| `APPLY_INGRESS` | 可選 | 預設 `1`；設 `0` 可先不建 Ingress |

---

## 3.（可選）GHCR 私有映像 → imagePullSecrets

```bash
kubectl apply -f 00-namespace.yaml

kubectl -n ky-super-openamic create secret docker-registry registry-cred \
  --docker-server=ghcr.io \
  --docker-username='<GitHub用戶名>' \
  --docker-password='<PAT，需 read:packages>' \
  --docker-email='<email>'
```

然後在 `03-deployment.yaml` 取消註解：

```yaml
imagePullSecrets:
  - name: registry-cred
```

---

## 4. 一鍵佈署到 K8S

```bash
cd k8s
set -a && source ./deploy.env && set +a
chmod +x ./apply.sh
./apply.sh
```

`apply.sh` 會：

1. 建立／更新 Namespace `ky-super-openamic`
2. 用 ENV 建立 Secret `openmaic-secrets`
3. Apply ConfigMap / Deployment / Service（及 Ingress，除非 `APPLY_INGRESS=0`）
4. `kubectl set image` 設成你的 `IMAGE`
5. 等待 rollout

等價一行（不寫 `deploy.env`）：

```bash
DATABASE_URL='postgres://USER:PASS@HOST:5432/DB' \
MINIMAX_API_KEY='sk-...' \
IMAGE='ghcr.io/owner/repo:sha-abc1234' \
./apply.sh
```

---

## 5. 驗證

```bash
kubectl -n ky-super-openamic get pods,svc,ingress
kubectl -n ky-super-openamic logs -l app.kubernetes.io/name=openmaic --tail=80
# 應看到：[AgentRunner] runner ... started
```

本機預覽（無 Ingress 時）：

```bash
kubectl -n ky-super-openamic port-forward svc/openmaic 3001:80
# 瀏覽器 http://localhost:3001
```

---

## 6. 之後更新

**只換映像（新 CI build）：**

```bash
export IMAGE='ghcr.io/owner/repo:sha-新的'
kubectl -n ky-super-openamic set image deployment/openmaic "openmaic=${IMAGE}"
kubectl -n ky-super-openamic rollout status deployment/openmaic
```

**改 DB／API Key：** 改 `deploy.env` 後再跑一次 `./apply.sh`（會更新 Secret 並 rollout）。

---

## 7. Git：什麼可以提交／什麼不能

| 可提交 | 不可提交（已 ignore） |
|--------|----------------------|
| `k8s/*.yaml`（無真實密碼） | `k8s/deploy.env` |
| `deploy.env.example` | `.env.local` |
| `apply.sh` / `DEPLOY.md` | 含真實 `DATABASE_URL`／Key 的檔案 |

提交前請依根目錄 **`AGENTS.md`** 做敏感資料掃描。

---

## 檔案對照

| 檔案 | 用途 |
|------|------|
| `.gitignore` | 忽略 `deploy.env` 等密鑰 |
| `deploy.env.example` | 參數範本 |
| `apply.sh` | 佈署腳本 |
| `00-namespace.yaml` … `05-ingress.yaml` | 集群資源 |
| `../.github/workflows/docker-ghcr.yml` | push 開發分支 → GHCR |
