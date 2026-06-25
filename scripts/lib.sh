#!/usr/bin/env sh
# ============================================================================
# lib.sh — shared helpers for the bash scripts (env discovery + pretty output)
# ============================================================================
# Resolves deployment outputs from azd if available, else from the ARM deployment.
# Source this from the other *.sh scripts: . "$(dirname "$0")/lib.sh"
# ============================================================================
set -eu

c_reset='\033[0m'; c_bold='\033[1m'; c_green='\033[32m'; c_yellow='\033[33m'; c_red='\033[31m'; c_cyan='\033[36m'
say()  { printf '%b%s%b\n' "$c_cyan" "$1" "$c_reset"; }
ok()   { printf '%b✓ %s%b\n' "$c_green" "$1" "$c_reset"; }
warn() { printf '%b! %s%b\n' "$c_yellow" "$1" "$c_reset"; }
die()  { printf '%b✗ %s%b\n' "$c_red" "$1" "$c_reset" >&2; exit 1; }
hdr()  { printf '\n%b== %s ==%b\n' "$c_bold" "$1" "$c_reset"; }

need() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

# Load deployment outputs into env vars. Prefers azd; falls back to ARM outputs.
load_env() {
  need az
  if command -v azd >/dev/null 2>&1 && azd env get-values >/dev/null 2>&1; then
    # azd exports the main.bicep outputs as env values.
    eval "$(azd env get-values | sed 's/^/export /')"
  fi
  : "${AZURE_RESOURCE_GROUP:=}"
  : "${APIM_NAME:=}"
  : "${APIM_GATEWAY_URL:=}"
  : "${GOVERNED_API_NAME:=azure-openai}"
  : "${CONTENT_SAFETY_NAME:=}"
  if [ -z "$APIM_NAME" ] || [ -z "$AZURE_RESOURCE_GROUP" ]; then
    die "Could not resolve APIM_NAME / AZURE_RESOURCE_GROUP. Run 'azd env get-values' or set them manually."
  fi
}
