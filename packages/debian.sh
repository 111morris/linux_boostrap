#!/usr/bin/env bash
#
# packages/debian.sh — logical name overrides for the Debian family
# (debian, ubuntu, linuxmint, pop, raspbian, elementary, ...).
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
    ['cc']='gcc'
    ['python']='python3'
    ['python-pip']='python3-pip'
    ['python-venv']='python3-venv'
    ['ssh-client']='openssh-client'
    ['fd']='fd-find'
    ['gpg']='gnupg'
    ['xz']='xz-utils'
    ['node']='nodejs'
)
