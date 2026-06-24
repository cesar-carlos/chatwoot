#!/usr/bin/env bash
# FORK: export single-history pilot pre/post metrics to CSV
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
exec bundle exec rails runner bin/fork-pilot-single-history-metrics.rb "$@"
