#!/bin/bash

# ============================================================
# Raven's Debian Disk Audit & Cleanup Utility
# ============================================================
#
# Usage:
#
#   chmod +x disk-audit.sh
#   sudo ./disk-audit.sh
#
# Reports are saved to:
#
#   ~/system-reports/
#
# ============================================================

set -u

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
RESET='\033[0m'

# ------------------------------------------------------------
# User detection
# ------------------------------------------------------------

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

if [[ -z "$REAL_HOME" ]]; then
    REAL_HOME="/home/$REAL_USER"
fi

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo
    echo "This script must be run with sudo."
    echo
    echo "Run:"
    echo
    echo "    sudo $0"
    echo
    exit 1
fi

# ------------------------------------------------------------
# Report setup
# ------------------------------------------------------------

REPORT_DIR="$REAL_HOME/sys_cleaner/reports"

mkdir -p "$REPORT_DIR"

chown "$REAL_USER":"$(id -gn "$REAL_USER")" "$REPORT_DIR"

TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"

REPORT_FILE="$REPORT_DIR/disk-audit-$TIMESTAMP.txt"

touch "$REPORT_FILE"

chown "$REAL_USER":"$(id -gn "$REAL_USER")" "$REPORT_FILE"

# ------------------------------------------------------------
# Starting information
# ------------------------------------------------------------

START_TIME=$(date +%s)

RUNNING_KERNEL="$(uname -r)"

ROOT_FREE_BEFORE=$(df -B1 / | awk 'NR==2 {print $4}')
ROOT_USED_BEFORE=$(df -B1 / | awk 'NR==2 {print $3}')

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

header() {

    echo
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${WHITE}  $1${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo
}


status() {
    echo -e "${BLUE}➜${RESET} $1"
}


success() {
    echo -e "${GREEN}✔${RESET} $1"
}


warning() {
    echo -e "${YELLOW}⚠${RESET} $1"
}


error() {
    echo -e "${RED}✘${RESET} $1"
}


pause() {

    echo
    read -rp "Press Enter to continue..."
}


yes_no() {

    local prompt="$1"

    read -rp "$prompt [y/N]: " answer

    case "${answer,,}" in
        y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


format_bytes() {

    numfmt \
        --to=iec \
        --suffix=B \
        "$1" 2>/dev/null || echo "$1 bytes"
}


spinner() {

    local pid="$1"
    local message="$2"

    local frames=(
        "⠋"
        "⠙"
        "⠹"
        "⠸"
        "⠼"
        "⠴"
        "⠦"
        "⠧"
        "⠇"
        "⠏"
    )

    local i=0

    printf "\033[?25l"

    while kill -0 "$pid" 2>/dev/null; do

        printf "\r${MAGENTA}%s${RESET} %s" \
            "${frames[$i]}" \
            "$message"

        i=$(( (i + 1) % ${#frames[@]} ))

        sleep 0.1

    done

    printf "\r\033[K"
    printf "\033[?25h"
}


# ------------------------------------------------------------
# Logging helper
# ------------------------------------------------------------

log_section() {

    local title="$1"

    {
        echo
        echo "============================================================"
        echo "$title"
        echo "============================================================"
        echo
    } >> "$REPORT_FILE"
}


# ------------------------------------------------------------
# Run command and save output
# ------------------------------------------------------------

run_report_command() {

    local title="$1"
    shift

    log_section "$title"

    "$@" 2>&1 | tee -a "$REPORT_FILE"
}


# ------------------------------------------------------------
# Banner
# ------------------------------------------------------------

clear

if command -v figlet >/dev/null 2>&1; then

    if command -v lolcat >/dev/null 2>&1; then
        figlet "Disk Doctor" | lolcat
    else
        figlet "Disk Doctor"
    fi

else

    header "DISK DOCTOR"

fi

echo
echo -e "${CYAN}Debian Disk Audit & Cleanup Utility${RESET}"
echo

echo "User:           $REAL_USER"
echo "Hostname:       $(hostname)"
echo "Running kernel: $RUNNING_KERNEL"
echo "Report file:"
echo
echo "  $REPORT_FILE"
echo

# ------------------------------------------------------------
# Report header
# ------------------------------------------------------------

{
    echo "Raven's Debian Disk Audit"
    echo
    echo "Generated: $(date)"
    echo "Hostname: $(hostname)"
    echo "User: $REAL_USER"
    echo "Running kernel: $RUNNING_KERNEL"
    echo
} >> "$REPORT_FILE"

# ============================================================
# MAIN AUDIT
# ============================================================

header "FILESYSTEM OVERVIEW"

run_report_command \
    "Filesystem Usage - df -h" \
    df -h


header "ROOT FILESYSTEM"

status "Scanning root filesystem..."

ROOT_SCAN_TMP=$(mktemp)

du -xhd1 / 2>/dev/null \
    | sort -h \
    > "$ROOT_SCAN_TMP" &

SCAN_PID=$!

spinner \
    "$SCAN_PID" \
    "Scanning root filesystem"

wait "$SCAN_PID"

cat "$ROOT_SCAN_TMP"

log_section "Root Filesystem Breakdown"
cat "$ROOT_SCAN_TMP" >> "$REPORT_FILE"

rm -f "$ROOT_SCAN_TMP"


# ============================================================
# /usr analysis
# ============================================================

header "/USR ANALYSIS"

status "Scanning /usr..."

USR_SCAN_TMP=$(mktemp)

du -xhd1 /usr 2>/dev/null \
    | sort -h \
    > "$USR_SCAN_TMP" &

SCAN_PID=$!

spinner \
    "$SCAN_PID" \
    "Scanning /usr"

wait "$SCAN_PID"

cat "$USR_SCAN_TMP"

log_section "/usr Breakdown"
cat "$USR_SCAN_TMP" >> "$REPORT_FILE"

rm -f "$USR_SCAN_TMP"


# ------------------------------------------------------------
# /usr top directories
# ------------------------------------------------------------

echo
status "Finding largest directories under /usr..."

USR_TOP_TMP=$(mktemp)

du -xhd2 /usr 2>/dev/null \
    | sort -rh \
    | head -40 \
    > "$USR_TOP_TMP" &

SCAN_PID=$!

spinner \
    "$SCAN_PID" \
    "Finding large /usr directories"

wait "$SCAN_PID"

cat "$USR_TOP_TMP"

log_section "Largest Directories Under /usr"
cat "$USR_TOP_TMP" >> "$REPORT_FILE"

rm -f "$USR_TOP_TMP"


# ============================================================
# /usr/local analysis
# ============================================================

header "/USR/LOCAL ANALYSIS"

status "Scanning manually installed/local software..."

LOCAL_TMP=$(mktemp)

du -xhd2 /usr/local 2>/dev/null \
    | sort -rh \
    | head -40 \
    > "$LOCAL_TMP" &

SCAN_PID=$!

spinner \
    "$SCAN_PID" \
    "Scanning /usr/local"

wait "$SCAN_PID"

cat "$LOCAL_TMP"

log_section "/usr/local Breakdown"
cat "$LOCAL_TMP" >> "$REPORT_FILE"

rm -f "$LOCAL_TMP"


# ============================================================
# Installed package analysis
# ============================================================

header "LARGEST INSTALLED PACKAGES"

PACKAGE_TMP=$(mktemp)

dpkg-query \
    -Wf '${db:Status-Abbrev}\t${Installed-Size}\t${Package}\n' \
    | awk '$1 == "ii" {printf "%s\t%s\n", $2, $3}' \
    | sort -nr \
    | head -50 \
    > "$PACKAGE_TMP"

awk '{
    printf "%8.1f MB  %s\n", $1/1024, $2
}' "$PACKAGE_TMP"

log_section "Largest Installed Packages"

awk '{
    printf "%8.1f MB  %s\n", $1/1024, $2
}' "$PACKAGE_TMP" >> "$REPORT_FILE"


# ============================================================
# Kernel analysis
# ============================================================

header "KERNEL STATUS"

echo "Running kernel:"
echo
echo "    $RUNNING_KERNEL"
echo

log_section "Kernel Status"

{
    echo "Running kernel:"
    echo "$RUNNING_KERNEL"
    echo
} >> "$REPORT_FILE"

dpkg-query \
    -Wf '${db:Status-Abbrev}\t${Installed-Size}\t${Package}\n' \
    'linux-image-*' \
    2>/dev/null \
    | tee -a "$REPORT_FILE"

echo


# ------------------------------------------------------------
# Kernel meta-package
# ------------------------------------------------------------

echo
status "Checking Debian kernel meta-package..."

META_STATUS=$(dpkg-query \
    -W \
    -f='${db:Status-Abbrev}' \
    linux-image-amd64 \
    2>/dev/null || true)

if [[ "$META_STATUS" == "ii " ]]; then

    success "linux-image-amd64 is installed."

else

    warning "linux-image-amd64 is not fully installed."

    echo

    apt-cache policy linux-image-amd64 \
        | tee -a "$REPORT_FILE"

    echo

    if yes_no "Install/reinstall linux-image-amd64?"; then

        apt install linux-image-amd64

    else

        warning "Kernel meta-package installation skipped."

    fi
fi


# ============================================================
# Residual configuration packages
# ============================================================

header "RESIDUAL PACKAGE CONFIGURATIONS"

RC_TMP=$(mktemp)

dpkg -l \
    | awk '$1 == "rc" {print $2}' \
    > "$RC_TMP"

RC_COUNT=$(wc -l < "$RC_TMP")

echo "Residual configuration packages found: $RC_COUNT"
echo

log_section "Residual Configuration Packages"

cat "$RC_TMP" >> "$REPORT_FILE"

if (( RC_COUNT > 0 )); then

    cat "$RC_TMP"

    echo

    if yes_no "Purge all residual package configurations?"; then

        while IFS= read -r package; do

            [[ -z "$package" ]] && continue

            echo
            status "Purging $package"

            dpkg --purge "$package"

        done < "$RC_TMP"

    else

        warning "Residual package cleanup skipped."

    fi

else

    success "No residual package configurations found."

fi

rm -f "$RC_TMP"


# ============================================================
# Partially configured packages
# ============================================================

header "PARTIAL PACKAGE STATES"

IC_TMP=$(mktemp)

dpkg-query \
    -Wf '${db:Status-Abbrev}\t${Package}\n' \
    | awk '$1 == "ic" {print $2}' \
    > "$IC_TMP"

IC_COUNT=$(wc -l < "$IC_TMP")

echo "Packages in 'ic' state: $IC_COUNT"
echo

log_section "Packages in IC State"

cat "$IC_TMP" >> "$REPORT_FILE"

if (( IC_COUNT > 0 )); then

    cat "$IC_TMP"

    echo

    warning "These packages are not fully installed."

    echo
    echo "Do not automatically delete kernel-related entries without"
    echo "checking the currently running kernel first."

fi


# ============================================================
# Selective package removal
# ============================================================

header "SELECTIVE PACKAGE REMOVAL"

echo "The 50 largest installed packages are shown below."
echo

awk '{
    printf "%3d) %8.1f MB  %s\n",
        NR,
        $1/1024,
        $2
}' "$PACKAGE_TMP"

echo
echo -e "${YELLOW}Only remove software you recognize and no longer need.${RESET}"
echo
echo "Enter package numbers separated by spaces."
echo
echo "Example:"
echo
echo "    2 5 9"
echo
echo "Press Enter to skip package removal."
echo

read -rp "Packages to purge: " selections

if [[ -n "$selections" ]]; then

    SELECTED_PACKAGES=()

    for number in $selections; do

        if [[ "$number" =~ ^[0-9]+$ ]]; then

            PACKAGE=$(sed -n "${number}p" "$PACKAGE_TMP" \
                | awk '{print $2}')

            if [[ -n "$PACKAGE" ]]; then
                SELECTED_PACKAGES+=("$PACKAGE")
            fi

        fi

    done

    if (( ${#SELECTED_PACKAGES[@]} > 0 )); then

        echo
        echo "You selected:"
        echo

        for package in "${SELECTED_PACKAGES[@]}"; do
            echo "    $package"
        done

        echo

        if yes_no "Purge these packages?"; then

            apt purge "${SELECTED_PACKAGES[@]}"

        else

            warning "Package removal cancelled."

        fi

    fi

else

    warning "Selective package removal skipped."

fi


rm -f "$PACKAGE_TMP"


# ============================================================
# /usr/local inspection
# ============================================================

header "MANUAL SOFTWARE CHECK"

echo "Large directories under /usr/local may have been installed"
echo "outside Debian's package manager."
echo

LOCAL_DIR_TMP=$(mktemp)

find /usr/local \
    -mindepth 1 \
    -maxdepth 2 \
    -type d \
    -print0 2>/dev/null \
    | while IFS= read -r -d '' dir; do

        size=$(du -sx "$dir" 2>/dev/null | awk '{print $1}')

        if [[ -n "$size" ]]; then
            printf "%s\t%s\n" "$size" "$dir"
        fi

    done \
    | sort -nr \
    | head -30 \
    > "$LOCAL_DIR_TMP"


awk '{
    printf "%8.1f MB  %s\n", $1/1024, $2
}' "$LOCAL_DIR_TMP"

log_section "Large /usr/local Directories"

awk '{
    printf "%8.1f MB  %s\n", $1/1024, $2
}' "$LOCAL_DIR_TMP" >> "$REPORT_FILE"

echo
echo -e "${YELLOW}This script will NOT automatically delete anything from /usr/local.${RESET}"
echo
echo "Manual installations can contain important software."
echo

rm -f "$LOCAL_DIR_TMP"


# ============================================================
# APT cleanup
# ============================================================

header "APT CLEANUP"

if yes_no "Run apt autoremove --purge?"; then

    apt autoremove --purge

else

    warning "APT autoremove skipped."

fi

echo

if yes_no "Clean downloaded APT package cache?"; then

    apt clean

else

    warning "APT cache cleanup skipped."

fi


# ============================================================
# Package health
# ============================================================

header "PACKAGE HEALTH"

status "Running apt-get check..."

apt-get check \
    2>&1 \
    | tee -a "$REPORT_FILE"


# ============================================================
# Final disk analysis
# ============================================================

header "FINAL DISK STATUS"

run_report_command \
    "Final Filesystem Usage" \
    df -h


echo
status "Rechecking root filesystem..."

du -xhd1 / 2>/dev/null \
    | sort -h \
    | tee -a "$REPORT_FILE"


# ------------------------------------------------------------
# Space recovered
# ------------------------------------------------------------

ROOT_FREE_AFTER=$(df -B1 / | awk 'NR==2 {print $4}')
ROOT_USED_AFTER=$(df -B1 / | awk 'NR==2 {print $3}')

SPACE_GAINED=$((ROOT_FREE_AFTER - ROOT_FREE_BEFORE))

if (( SPACE_GAINED < 0 )); then
    SPACE_GAINED=0
fi


# ------------------------------------------------------------
# Runtime
# ------------------------------------------------------------

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

MINUTES=$((RUNTIME / 60))
SECONDS=$((RUNTIME % 60))


# ============================================================
# Summary
# ============================================================

header "AUDIT SUMMARY"

echo "Root filesystem before:"
echo

df -h / | tail -1

echo

echo "Free space before:"
echo "    $(format_bytes "$ROOT_FREE_BEFORE")"

echo

echo "Free space after:"
echo "    $(format_bytes "$ROOT_FREE_AFTER")"

echo

echo "Estimated space recovered:"
echo "    $(format_bytes "$SPACE_GAINED")"

echo

echo "Runtime:"
printf "    %dm %ds\n" "$MINUTES" "$SECONDS"

echo

echo "Full report saved to:"
echo
echo "    $REPORT_FILE"

echo


# ------------------------------------------------------------
# Report summary
# ------------------------------------------------------------

log_section "Final Summary"

{
    echo "Free space before: $(format_bytes "$ROOT_FREE_BEFORE")"
    echo "Free space after:  $(format_bytes "$ROOT_FREE_AFTER")"
    echo "Space recovered:   $(format_bytes "$SPACE_GAINED")"
    echo
    echo "Runtime: ${MINUTES}m ${SECONDS}s"
} >> "$REPORT_FILE"


# ------------------------------------------------------------
# Final artwork
# ------------------------------------------------------------

if command -v lolcat >/dev/null 2>&1; then

cat <<'EOF' | lolcat

╔════════════════════════════════════════════════════╗
║                                                    ║
║              DISK AUDIT COMPLETE                   ║
║                                                    ║
╚════════════════════════════════════════════════════╝

                 (\_/)
                 ( •_•)
                / >🔍

          Filesystem investigated.

EOF

else

echo "============================================================"
echo "               DISK AUDIT COMPLETE"
echo "============================================================"

fi

success "Report saved successfully."

echo
