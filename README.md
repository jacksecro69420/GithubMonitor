# GithubMonitor

Menubar-only macOS app (Tuist + SwiftUI) to show your recently updated open GitHub pull requests.

## Setup

1. Install Tuist if needed.
2. Add your OAuth client ID in `Project.swift`:
   - `GitHubOAuthClientID` in `infoPlist`, replacing `__GITHUB_CLIENT_ID__`
3. Generate and build:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
TUIST_SKIP_UPDATE_CHECK=1 tuist build GithubMonitor --configuration Debug
```

4. Run:

```bash
./run-menubar.sh
```

## Login Flow

- Uses GitHub OAuth Device Flow.
- The app opens `https://github.com/login/device` and displays a one-time code.
- Access token is stored in macOS Keychain.
- `Sign out` removes the saved token.

## Scripts

- `run-menubar.sh`: stop existing process, build, and launch app.
- `stop-menubar.sh`: stop running app process.
