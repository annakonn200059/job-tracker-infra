#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

kubectl apply -f k8s/raw/00-namespace.yaml -f k8s/raw/postgres.yaml -f k8s/raw/ingress.yaml

for app in api web worker; do
  tag=$(make -s --no-print-directory -C "../job-tracker-$app" tag)
  echo "$app → $tag"
  sed "s/REPLACE_ME/$tag/" "k8s/raw/$app.yaml" | kubectl apply -f -
done
Make it executable:
chmod +x scripts/deploy-raw.sh