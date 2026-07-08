#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Shared function library for the Helm/Kubernetes/ACR reusable stages.
#
# This is the GitHub Actions equivalent of the GitLab `footer.yaml` `.fcts`
# anchor. GitHub Actions runs every `run:` block in its own shell, so unlike
# GitLab (where before_script/script share one shell per job) functions do
# NOT persist between steps automatically. Each step that needs a function
# from here must `source` this file first:
#
#   - name: Deploy
#     run: |
#       source "$GITHUB_WORKSPACE/_stages/scripts/functions.sh"
#       ensure_namespace "${{ inputs.namespace }}"
#       ...
#
# Callers check this file out from the `stages` repo into `_stages/` before
# sourcing it (see any workflow in .github/workflows/ for the checkout step).
# ─────────────────────────────────────────────────────────────────────────────

# ensure_namespace <namespace>
# Creates the namespace if it does not already exist. Idempotent.
# Direct port of footer.yaml's ensure_namespace (GitLab), same check-then-create
# shape, just using kubectl the same way.
function ensure_namespace() {
  if [ -z "$1" ]; then
    echo "Usage: ensure_namespace <namespace>"
    return 1
  fi
  local ns="$1"
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    echo "Namespace '$ns' already exists"
  else
    echo "Namespace '$ns' not found — creating it"
    kubectl create namespace "$ns"
  fi
}

# get_chart_version <chart_path>
# Reads the `version:` field out of Chart.yaml. Same job as footer.yaml's
# get_chart_version, just reimplemented without relying on GitLab-only egrep
# quirks.
function get_chart_version() {
  if [ -z "$1" ]; then
    echo "Usage: get_chart_version <chart_path>"
    return 1
  fi
  grep -E '^version:' "$1/Chart.yaml" | awk '{print $2}' | tr -d '"'
}

# acr_login <login_server> <username> <password>
# Logs Helm's OCI client + the local docker/helm CLI into ACR.
# Equivalent of footer.yaml's helm_init, but ACR (OCI) instead of a Harbor
# chart repo — ACR needs `helm registry login`, not `helm repo add`.
function acr_login() {
  if [ -z "$3" ]; then
    echo "Usage: acr_login <login_server> <username> <password>"
    return 1
  fi
  local login_server="$1" username="$2" password="$3"
  echo "$password" | helm registry login "$login_server" \
    --username "$username" --password-stdin
}

# helm_push_chart <chart_path> <login_server> [chart_repo_path]
# Packages the chart and pushes it to ACR as an OCI artifact.
# Equivalent of footer.yaml's helm_push, targeting oci://<acr>/helm instead
# of a Harbor chartrepo URL.
function helm_push_chart() {
  if [ -z "$2" ]; then
    echo "Usage: helm_push_chart <chart_path> <login_server> [chart_repo_path]"
    return 1
  fi
  local chart_path="$1" login_server="$2" chart_repo_path="${3:-helm}"
  local version
  version=$(get_chart_version "$chart_path")
  if [ -z "$version" ]; then
    echo "Could not read chart version from $chart_path/Chart.yaml"
    return 1
  fi

  echo "Packaging chart at $chart_path (version $version)..."
  local package_dir
  package_dir=$(mktemp -d)
  helm package "$chart_path" --destination "$package_dir"

  local chart_name
  chart_name=$(basename "$chart_path")
  echo "Pushing ${chart_name}-${version}.tgz to oci://${login_server}/${chart_repo_path}"
  helm push "${package_dir}/${chart_name}-${version}.tgz" "oci://${login_server}/${chart_repo_path}"

  rm -rf "$package_dir"
  echo "$version"
}

# wait_deploy <release_name> <namespace>
# Waits for every Deployment/StatefulSet/DaemonSet in a Helm release to finish
# rolling out. Equivalent of footer.yaml's wait_deploy2 — kept here for manual
# use or for stages that don't pass `--wait` to `helm upgrade`.
function wait_deploy() {
  if [ -z "$2" ]; then
    echo "Usage: wait_deploy <release_name> <namespace>"
    return 1
  fi
  local release_name="$1" ns="$2"
  local resources
  resources=$(helm get manifest "$release_name" -n "$ns" \
    | yq -r 'select((.kind=="Deployment") or (.kind=="StatefulSet") or (.kind=="DaemonSet")) | .kind+"/"+.metadata.name')

  for resource in $resources; do
    echo "Waiting for rollout: $resource"
    kubectl --namespace "$ns" rollout status "$resource"
  done
}

# resolve_values_file <service_dir> <environment>
# Looks for an environment-specific values file first (values-<env>.yaml),
# falling back to the plain values.yaml. Mirrors the intent of footer.yaml's
# set_values_yaml (per-environment file lookup), simplified since our chart
# takes one values file per service rather than searching env vars.
function resolve_values_file() {
  if [ -z "$2" ]; then
    echo "Usage: resolve_values_file <service_dir> <environment>"
    return 1
  fi
  local service_dir="$1" environment="$2"
  local env_specific="${service_dir}/values-${environment}.yaml"
  local default_file="${service_dir}/values.yaml"

  if [ -f "$env_specific" ]; then
    echo "$env_specific"
  elif [ -f "$default_file" ]; then
    echo "$default_file"
  else
    echo "No values file found: tried $env_specific and $default_file" >&2
    return 1
  fi
}
