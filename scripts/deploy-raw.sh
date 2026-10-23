#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

env_file=local/postgres.env
if [[ ! -f $env_file ]]; then
  echo "missing $env_file: copy $env_file.example and set a password" >&2
  exit 1
fi

kubectl apply -f k8s/raw/00-namespace.yaml -f k8s/raw/config.yaml

kubectl -n job-tracker create secret generic postgres --from-env-file="$env_file" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f k8s/raw/postgres.yaml -f k8s/raw/ingress.yaml

# Changes to the ConfigMaps or the Secret alter the pod template, which triggers a rollout.
config_hash=$(cat k8s/raw/config.yaml "$env_file" | shasum -a 256 | cut -c1-16)

cluster=jobtracker
nodes=$(k3d node list --no-headers | awk -v c="$cluster" '$3 == c && ($2 == "server" || $2 == "agent") { print $1 }')

# True when every node already has the image, so the pull can't fail.
in_cluster() {
  local node
  for node in $nodes; do
    docker exec "$node" crictl inspecti -q "docker.io/library/$1" >/dev/null 2>&1 || return 1
  done
}

for app in api web worker; do
  tag=$(make -s --no-print-directory -C "../job-tracker-$app" tag)
  echo "$app → $tag"
  # A -dirty tag doesn't change when the working tree does, so the image under it
  # may be stale: always rebuild those. Clean tags only need building once.
  if [[ $tag == *-dirty ]] || ! in_cluster "job-tracker-$app:$tag"; then
    target=import
    [[ $app == web ]] && target=import-web
    make -s --no-print-directory -C "../job-tracker-$app" "$target" CLUSTER="$cluster"
  fi
  sed -e "s/REPLACE_ME/$tag/" -e "s/CONFIG_HASH/$config_hash/" "k8s/raw/$app.yaml" | kubectl apply -f -
done
