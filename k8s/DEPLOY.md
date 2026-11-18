# OpenMAIC → Kubernetes 佈署指南

Namespace：**`open-maic`**  
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
kubectl / ./apply.sh  →  open-maic
        │
        ▼
Pods 連外掛 Postgres（DATABASE_URL）
```

---

## 0. 前置條件

| 項目 | 說明 |
|------|------|
| `kubectl` | 已連上校內集群，可操作 `open-maic` |
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
NAMESPACE=open-maic

DATABASE_URL=postgres://USER:PASSWORD@PG_HOST:5432/DB_NAME
OPENAI_API_KEY=ark-你的火山方舟key
OPENAI_BASE_URL=https://ark.cn-beijing.volces.com/api/v3
OPENAI_MODELS=doubao-seed-2-1-pro-260628
IMAGE=ghcr.io/<owner>/<repo>:agent-runtime

# Private GHCR — apply.sh 會建立 secret/registry-cred
GHCR_USERNAME=你的GitHub用戶名
GHCR_TOKEN=ghp_你的PAT_需read_packages
```

| 變數 | 必填 | 說明 |
|------|------|------|
| `DATABASE_URL` | ✅ | Postgres 連線字串 |
| `OPENAI_API_KEY` | ✅ | 火山方舟 API Key。`OPENAI_BASE_URL` 預設 `https://ark.cn-beijing.volces.com/api/v3`，模型預設 `doubao-seed-2-1-pro-260628` |
| `IMAGE` | ✅ | GHCR 映像 tag（建議用 `sha-…` 鎖定版本） |
| `GHCR_USERNAME` | ✅ | GitHub 用戶名 |
| `GHCR_TOKEN` | ✅ | PAT（至少 `read:packages`） |
| `APPLY_INGRESS` | 可選 | 預設 `1`；設 `0` 可先不建 Ingress |

ConfigMap `openmaic-config` 另含 `ANONYMOUS_COOKIE_SECURE=0`：校內 MetalLB 走 **HTTP** 時必須關閉，否則瀏覽器不存 `anonymous_id`，`/api/agent/sessions/:id` 會一直 404。HTTPS 終止後再改成 `1`。

---

## 3. 一鍵佈署到 K8S

```bash
cd k8s
set -a && source ./deploy.env && set +a
chmod +x ./apply.sh
./apply.sh
```

`apply.sh` 會：

1. 建立／更新 Namespace `open-maic`
2. 建立／更新 `registry-cred`（GHCR pull）與 `openmaic-secrets`
3. Apply ConfigMap / Deployment / Service（及 Ingress，除非 `APPLY_INGRESS=0`）
4. `kubectl set image` 設成你的 `IMAGE`
5. 等待 rollout

等價一行（不寫 `deploy.env`）：

```bash
DATABASE_URL='postgres://USER:PASS@HOST:5432/DB' \
OPENAI_API_KEY='ark-...' \
IMAGE='ghcr.io/owner/repo:sha-abc1234' \
GHCR_USERNAME='you' \
GHCR_TOKEN='ghp_...' \
./apply.sh
```

---

## 4. 驗證

```bash
kubectl -n open-maic get pods,svc,ingress
kubectl -n open-maic logs -l app.kubernetes.io/name=openmaic --tail=80
# 應看到：[AgentRunner] runner ... started
```

### 區網訪問（LoadBalancer）

`openmaic` Service 為 **LoadBalancer**（MetalLB）。取得 IP：

```bash
kubectl -n open-maic get svc openmaic
# EXTERNAL-IP 例如 YOUR_LB_IP
```

同一 LAN 內瀏覽器打開：`http://<EXTERNAL-IP>/`（埠 80）。

本機 port-forward 僅供臨時除錯，正式使用請用上述區網 IP。

---

## 5. 之後更新

**只換映像（新 CI build）：**

```bash
export IMAGE='ghcr.io/owner/repo:sha-新的'
kubectl -n open-maic set image deployment/openmaic "openmaic=${IMAGE}"
kubectl -n open-maic rollout status deployment/openmaic
```

**改 DB／API Key：** 改 `deploy.env` 後再跑一次 `./apply.sh`（會更新 Secret 並 rollout）。

---

## 6. Git：什麼可以提交／什麼不能

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
