#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/config/software.conf"

source "$SCRIPT_DIR/modules/system.sh"
source "$SCRIPT_DIR/modules/git.sh"
source "$SCRIPT_DIR/modules/python.sh"
source "$SCRIPT_DIR/modules/node.sh"
source "$SCRIPT_DIR/modules/ssh.sh"
source "$SCRIPT_DIR/modules/shell.sh"

if [[ "${INSTALL_DOCKER:-false}" == "true" ]]; then
    source "$SCRIPT_DIR/modules/docker.sh"
fi

if [[ "${INSTALL_RUST:-false}" == "true" ]]; then
    source "$SCRIPT_DIR/modules/rust.sh"
fi

if [[ "${INSTALL_GO:-false}" == "true" ]]; then
    source "$SCRIPT_DIR/modules/go.sh"
fi

