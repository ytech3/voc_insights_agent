# VOC Insights Agent — Codex Session Guide

This file is auto-loaded by Codex at the start of every session. It captures
the deployment architecture and the exact steps needed to push updates efficiently.

---

## Architecture overview

| Component | Name | What it is |
|---|---|---|
| Chat widget | `rays-voc-agent` | Azure Static Web App — vanilla HTML/CSS/JS |
| AI backend | `rays-voc-proxy` | Azure Function App — Python 3.11, Flex Consumption |
| Data | Snowflake | VOC survey data; connection via private key in App Settings |
| Host | `rg-voc-agent` | Azure resource group, subscription "TBRAYS Azure Main" |

**Widget URL**: `https://orange-dune-0e3e6b610.7.azurestaticapps.net`  
**Function URL**: `https://rays-voc-proxy-dxf8bahjhhbnh4bx.eastus2-01.azurewebsites.net`

---

## Where to edit code

| What you want to change | File to edit |
|---|---|
| Starter questions, UI copy, colors, layout | `Dashboard/azure_deploy/webapp/app.js` or `index.html` |
| AI behavior, prompts, rounding, caching | `Dashboard/azure_deploy/function/function_app.py` |
| SQL the AI can generate | `voc_semantic_model.yaml` |

---

## Deploying changes

> Full step-by-step instructions are in **`Dashboard/DEPLOY.md`**.
> The quick version is below.

### Frontend (HTML / JS / CSS changes)

The Static Web App uses provider type `SwaCli` — GitHub Actions token validation
**does not work**. The only working deploy method is the SWA CLI.

**From local terminal** (Azure CLI + Node.js installed by IT):

```powershell
# Get the deployment token once from the portal:
# Portal → Static Web App (rays-voc-agent) → Settings → Manage deployment token → Copy
# Save that token in 1Password. Then:

npx --yes @azure/static-web-apps-cli deploy "C:\Users\ytaketani\Music\ytaketani\voc_insights_agent\Dashboard\azure_deploy\webapp" --deployment-token "PASTE_TOKEN_HERE" --env production
```

Wait for `✔ Project deployed to https://orange-dune-0e3e6b610.7.azurestaticapps.net`.  
Hard-refresh Tableau (`Ctrl+Shift+R`) to see the change.

**From Azure Cloud Shell** (browser-based, no local tools needed):

```bash
# In Cloud Shell — one-time setup:
npm install -g @azure/static-web-apps-cli

# Every deploy:
unzip -o webapp.zip -d webapp && cd webapp
swa deploy . --env production --deployment-token "PASTE_TOKEN_HERE"
```

### Backend (Python function changes)

The Function App deploys via GitHub Actions (workflow: `.github/workflows/patch19_rays-voc-proxy.yml`).  
Push to the `patch19` branch and the workflow triggers automatically.

```powershell
git add Dashboard/azure_deploy/function/function_app.py
git commit -m "your change description"
git push origin patch19
```

The workflow takes ~20 minutes (installs `snowflake-connector-python` + bundles packages).
Monitor at: GitHub → Actions tab.

**Verify after deploy:**
```powershell
curl https://rays-voc-proxy-dxf8bahjhhbnh4bx.eastus2-01.azurewebsites.net/api/health
# Expected: {"status":"ok","account":"HTA92307"}
```

**From Cloud Shell** (faster, bypasses GitHub Actions):

```bash
unzip -o function.zip -d function && cd function
func azure functionapp publish rays-voc-proxy --python
```

---

## Key constraints

- **Local installs now work (as of 2026-05-23)** — MSI installers and `npm install -g` both succeed; no IT ticket needed for routine CLI tools.
  Confirmed installed locally: Azure CLI (`az`), Node.js/npm, Git, `swa` (Static Web Apps CLI), `func` (Azure Functions Core Tools v4).
  Note: `npm install -g azure-functions-core-tools@4` leaves the native binaries as a ~570 MB zip in `%APPDATA%\npm\node_modules\azure-functions-core-tools\bin\`. If `func --version` errors with `ENOENT spawn ...\bin\func`, manually `Expand-Archive` the zip and delete it.
- **Kudu/SCM endpoint is blocked** on the corporate network — `*.scm.azurewebsites.net` is unreachable. Use Cloud Shell or GitHub Actions for deploys, not local `func publish`.
- **Static Web App deployment token** — treat like a password. Never commit to source files.
  Store in 1Password. Retrieve from: Portal → `rays-voc-agent` → Settings → Manage deployment token.
- **Snowflake private key** — exists only in Azure App Settings (encrypted at rest).
  Never commit to any file. Rotate via: Portal → Function App → Settings → Environment variables.
- **Cold start** — first `/api/chat` after a backend deploy takes 15-25 seconds. Normal.

---

## Running tests

```powershell
# Unit tests (no Azure/Snowflake needed)
cd C:\Users\ytaketani\Music\ytaketani\voc_insights_agent\Dashboard\tests
.\.python311\python.exe tier2_format_test.py

# Unit tests + live smoke against deployed function
.\.python311\python.exe tier2_format_test.py --url https://rays-voc-proxy-dxf8bahjhhbnh4bx.eastus2-01.azurewebsites.net
```

All 41 tests should pass.

---

## GitHub branch

Active development branch: **`patch19`**  
Main branch: `main`  
Merging patch19 → main is not required for deploys; the workflows trigger on `patch19`.

---

## If something breaks

1. **Widget blank / broken** — check browser console (F12). Usually a JS error in `app.js`.
2. **AI not responding** — hit the health endpoint (curl above). Check Log stream in the portal.
3. **Wrong answers** — check `voc_semantic_model.yaml` column descriptions and SQL examples.
4. **Logs** — Portal → `rays-voc-proxy` → Monitoring → Log stream (trigger the failing request, watch in real time).
5. **Rollback frontend** — re-deploy the previous `webapp/` folder with SWA CLI.
6. **Rollback backend** — Portal → `rays-voc-proxy` → Deployment Center → Logs → click prior deploy → Redeploy.

---

## Full deployment guide

See `Dashboard/DEPLOY.md` for the complete walkthrough including Cloud Shell setup,
App Settings changes, CORS adjustments, and a quick-reference card.
