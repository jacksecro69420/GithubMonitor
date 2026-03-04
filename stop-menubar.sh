#!/usr/bin/env bash
set -euo pipefail

pkill -x "GithubMonitor" >/dev/null 2>&1 || true
