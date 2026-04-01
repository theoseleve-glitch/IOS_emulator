#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This script must be sourced from your shell." >&2
  echo "Use: source ./scripts/env-wsl.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_SWIFT_HOME="${HOME}/.local/swift-6.3/usr"

export SWIFT_HOME="${SWIFT_HOME:-${DEFAULT_SWIFT_HOME}}"

if [[ ! -x "${SWIFT_HOME}/bin/swift" ]]; then
  echo "Swift toolchain not found at ${SWIFT_HOME}." >&2
  echo "Run ./scripts/bootstrap-wsl.sh first." >&2
  return 1 2>/dev/null || exit 1
fi

case ":${PATH}:" in
  *":${SWIFT_HOME}/bin:"*) ;;
  *) export PATH="${SWIFT_HOME}/bin:${PATH}" ;;
esac

export PHASE1_REPO_ROOT="${REPO_ROOT}"
