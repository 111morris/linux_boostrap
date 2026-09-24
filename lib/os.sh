#!/usr/bin/env bash
#
# lib/os.sh — distribution detection via /etc/os-release.
#
# Sets:  OS_ID  OS_NAME  OS_PRETTY  OS_VERSION  OS_VERSION_ID  OS_FAMILY  OS_ARCH
#
# OS_FAMILY is the only thing the rest of the system needs in order to pick a
# package manager and a package-name map:
#
#   debian  rhel  arch  suse  alpine
#
# The file is parsed, not sourced. OS_RELEASE_FILE may be overridden (tests).
#
# shellcheck shell=bash

OS_SUPPORTED_FAMILIES='debian rhel arch suse alpine'

_os_family_for_id() {
    case "${1:-}" in
        debian | ubuntu | linuxmint | pop | raspbian | elementary | zorin | kali)
            printf 'debian'
            ;;
        fedora | rhel | centos | rocky | almalinux | ol | amzn | nobara)
            printf 'rhel'
            ;;
        arch | manjaro | endeavouros | artix | garuda | cachyos)
            printf 'arch'
            ;;
        opensuse* | sles | suse | sled)
            printf 'suse'
            ;;
        alpine)
            printf 'alpine'
            ;;
        *)
            printf ''
            ;;
    esac
}

# OS_* results are cross-file globals consumed by bootstrap.sh, lib/pkg.sh
# and the tests.
# shellcheck disable=SC2034
detect_os() {
    local file="${OS_RELEASE_FILE:-/etc/os-release}"

    if [[ ! -r $file ]]; then
        die "Cannot read ${file}: unable to determine the Linux distribution."
    fi

    local id='' id_like='' name='' pretty='' version_id='' version=''
    local line key val

    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line == *=* ]] || continue
        key=${line%%=*}
        val=${line#*=}
        # strip one layer of surrounding quotes
        case "$val" in
            \"*\") val=${val#\"} val=${val%\"} ;;
            \'*\') val=${val#\'} val=${val%\'} ;;
        esac
        case "$key" in
            ID) id=${val,,} ;;
            ID_LIKE) id_like=${val,,} ;;
            NAME) name=$val ;;
            PRETTY_NAME) pretty=$val ;;
            VERSION_ID) version_id=$val ;;
            VERSION) version=$val ;;
        esac
    done <"$file"

    if [[ -z $id ]]; then
        die "Invalid ${file}: missing ID."
    fi

    OS_ID=$id
    OS_NAME=${name:-$id}
    OS_VERSION_ID=$version_id
    OS_VERSION=${version:-$version_id}
    OS_PRETTY=${pretty:-"${name:-$id}${version_id:+ $version_id}"}
    OS_ARCH=$(uname -m)

    OS_FAMILY=$(_os_family_for_id "$id")

    # Fall back to ID_LIKE (e.g. "custom" with ID_LIKE=fedora, or pop -> debian)
    if [[ -z $OS_FAMILY && -n $id_like ]]; then
        local token
        for token in $id_like; do
            OS_FAMILY=$(_os_family_for_id "$token")
            if [[ -n $OS_FAMILY ]]; then
                break
            fi
        done
    fi

    if [[ -z $OS_FAMILY ]]; then
        die "Unsupported distribution: ID='${id}' (ID_LIKE='${id_like:-none}'). Supported families: ${OS_SUPPORTED_FAMILIES}."
    fi
}
