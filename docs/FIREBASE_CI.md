# Firebase + GitHub Actions (Firestore rules)

## Automatic behavior (already in the repo)

- **Push to `main`** that changes `firestore.rules`, `firebase.json`, or the deploy workflow → **deploys** Firestore rules (if `FIREBASE_TOKEN` is set).
- **Pull requests** into `main` that touch those files → **dry-run** validation (same token requirement).

## One-command setup (local machine)

You still need a **one-time browser login** for Firebase (Google does not allow fully headless token creation).

### Windows (PowerShell, from repo root)

```powershell
.\scripts\setup-firebase-github-secret.ps1
```

Optional: after the secret is set, trigger the workflow once:

```powershell
.\scripts\setup-firebase-github-secret.ps1 -RunDeployWorkflow
```

### macOS / Linux

```bash
chmod +x scripts/setup-firebase-github-secret.sh
./scripts/setup-firebase-github-secret.sh
```

Optional:

```bash
./scripts/setup-firebase-github-secret.sh --run-workflow
```

### Prerequisites

| Tool | Install |
|------|--------|
| Node.js | [nodejs.org](https://nodejs.org/) |
| GitHub CLI `gh` | [cli.github.com](https://cli.github.com/) (Windows: `winget install GitHub.cli`) |

Run `gh auth login` once if you haven’t (the script will prompt).

### If you already have a CI token

```powershell
$env:FIREBASE_CI_TOKEN = "paste-token-here"
.\scripts\setup-firebase-github-secret.ps1 -SkipFirebaseLogin
```

```bash
FIREBASE_CI_TOKEN='paste-token-here' ./scripts/setup-firebase-github-secret.sh --skip-login
```

## Manual alternative

1. `npx firebase-tools login:ci` → copy token  
2. GitHub repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** → name `FIREBASE_TOKEN`  

## Verify

- **Actions** tab → workflow **Deploy Firestore rules** → latest run should succeed.  
- Firebase Console → Firestore → **Rules** → check **Published** time.
