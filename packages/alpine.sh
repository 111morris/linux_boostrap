#!/usr/bin/env bash
#
# packages/alpine.sh — logical name overrides for Alpine.
#
# Only names that DIFFER from the logical baseline are listed; everything else
# (git, curl, wget, tmux, htop, tree, jq, ripgrep, vim, make, tar, ...) is used
# as-is. A value may contain several packages (space separated).
# Keys are quoted so formatters never rewrite them.
#
# shellcheck shell=bash

# PKG_MAP is consumed by pkg_resolve in lib/pkg.sh when this file is sourced.
# shellcheck disable=SC2034
declare -gA PKG_MAP=(
    ['build-essential']='build-base'
    ['cc']='gcc'
    ['python']='python3'
    ['python-pip']='py3-pip'
    ['python-venv']='python3'
    ['ssh-client']='openssh'
    ['fd']='fd'
    ['gpg']='gnupg'
    ['node']='nodejs'
)
