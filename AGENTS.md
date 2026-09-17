# OpenMAIC — Agent 指引

本倉庫可能從 public upstream fork，且含校內／自架佈署設定。Agent 在本專案中必須遵守下列規則。

---

## 提交前強制檢查（每次 `git commit` 之前）

**在執行任何 `git commit` / `git push` 之前，必須先完成敏感資料掃描。**  
未通過則禁止提交；先改成佔位符或移出暫存區。

### 1. 確認暫存內容

```bash
git status --short
git diff --cached
```

確認沒有把本機密鑰檔加進去。

### 2. 掃描即將提交的內容

對 **staged** 與即將 `git add` 的路徑執行（依環境調整）：

```bash
# 常見密鑰／連線字串（命中真實值則停止提交）
git diff --cached -U0 | rg -i \
  'sk-api-|sk-ant-|sk-or-|ghp_|github_pat_|xox[baprs]-|AKIA[0-9A-Z]{16}|-----BEGIN .*PRIVATE KEY-----|postgres://[^:\s]+:[^@\s]+@'

# 本專案曾出現過的校內／本機敏感樣式（應使用佔位符）
git diff --cached -U0 | rg -n \
  'P_ssw0rd|10\.170\.254\.|openmaic-school-dev@|host\.docker\.internal.*Password'
```

也可用對檔案清單掃描：

```bash
git diff --cached --name-only | while read -r f; do
  [ -f "$f" ] || continue
  rg -n -i 'sk-api-|postgres://[^:]+:[^@]+@|PASSWORD|SECRET|API_KEY=.+' "$f" && echo "FAIL: $f"
done
```

### 3. 禁止提交的檔案／路徑

| 路徑 | 原因 |
|------|------|
| `.env` / `.env.local` / `.env.*.local` | 本機 API Key、連線字串 |
| `k8s/deploy.env` | 真實 `DATABASE_URL` / `MINIMAX_API_KEY` / `IMAGE` |
| 含真實密碼的 `**/secret*.yaml` | 應改由 `k8s/apply.sh` + ENV 注入 |
| 憑證、私鑰、kubeconfig | 一律不進 Git |

（上述多數已在 `.gitignore`；若被 `git add -f` 強制加入，提交前必須拿掉。）

### 4. 允許的「範例」寫法

文件與 example 檔只能使用佔位符，例如：

- `CHANGE_ME` / `YOUR_PG_HOST` / `REPLACE_ME` / `sk-replace-me` / `sk-...`
- `postgres://USER:PASS@HOST:5432/DB`
- `ghcr.io/YOUR_USER/openmaic:agent-runtime`

**不要**把真實校內 IP、真實 DB 密碼、真實 MiniMax／OpenAI Key 寫進會被 push 的 Markdown／YAML／腳本註解。

### 5. 通過標準

- [ ] `git diff --cached` 無真實 API Key／Token／私鑰  
- [ ] 無 `postgres://user:**真實密碼**@...`  
- [ ] 無本機專屬內網主機／帳密硬編碼（改 ENV／`deploy.env`）  
- [ ] `k8s/deploy.env`、`.env.local` 未出現在暫存區  
- [ ] 若曾誤提交密鑰：先輪換密鑰，再清歷史（勿只靠新 commit 覆蓋）

---

## 佈署相關提醒

- K8s：`DATABASE_URL`、`MINIMAX_API_KEY`、`IMAGE` 用環境變數或 `./k8s/apply.sh` 傳入，見 `k8s/README.md`。
- Docker 本機說明若在 `Docs/`，可能被 `.gitignore` 的 `/docs` 規則忽略；勿把真實密鑰寫進可追蹤文件。

---

## CI：Docker → GHCR

每次 push 到 **`feat/patricklai7528-dev`** 會跑 `.github/workflows/docker-ghcr.yml`：

- 建置含 Agent Runtime / Workbench 的 image
- 推送到 `ghcr.io/<owner>/<repo>`
- Tag：`latest`、`agent-runtime`、分支名、`sha-<short>`

部署時：

```bash
IMAGE='ghcr.io/<owner>/<repo>:sha-xxxxxxxx' \
DATABASE_URL='...' MINIMAX_API_KEY='...' \
./k8s/apply.sh
```

私有套件需在 GitHub Package 設定允許你的帳號／Actions 讀取；K8s 需 `imagePullSecrets`（見 `k8s/README.md`）。

---

## 一般行為

- 不要更新 git config；不要 force-push 受保護分支（除非使用者明確要求）。
- 使用者未要求時不要主動 commit；一旦要求 commit，**先跑完上面的敏感資料檢查**。
