#!/usr/bin/env bash
#
# packages/arch.sh — logical name overrides for the Arch family
# (arch, manjaro, endeavouros, artix, garuda, ...).
#
# Only names that DIFFER from the logical baseline are listed; everything else
# (git, curl, wget, python, tmux, htop, tree, jq, ripgrep, vim, make, tar, ...)
# is used as-is. A value may contain several packages (space separated).
# Keys are quoted so formatters never rewrite them.
#
# shellcheck shell=bash

# PKG_MAP is consumed by pkg_resolve in lib/pkg.sh when this file is sourced.
# shellcheck disable=SC2034
declare -gA PKG_MAP=(
    ['build-essential']='base-devel'
    ['cc']='gcc'
    ['python-venv']='python'
    ['ssh-client']='openssh'
    ['fd']='fd'
    ['gpg']='gnupg'
    ['node']='nodejs'
)
