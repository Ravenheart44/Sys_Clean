#!/bin/bash

# ============================================================
# Raven's Debian Maintenance Center
# ============================================================

set -u

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
RESET='\033[0m'

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

SCRIPT_DIR="$REAL_HOME/sys_cleaner"
AUDIT_SCRIPT="$SCRIPT_DIR/free.sh"
REPORT_DIR="$SCRIPT_DIR/reports"

mkdir -p "$REPORT_DIR"

# ------------------------------------------------------------
# Root check
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo
    echo -e "${RED}This utility must be run with sudo.${RESET}"
    echo
    echo "Run:"
    echo
    echo "    sudo $0"
    echo
    exit 1
fi

# ------------------------------------------------------------
# Helpers
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
# Banner
# ------------------------------------------------------------

show_banner() {

    clear

    if command -v figlet >/dev/null 2>&1; then

        if command -v lolcat >/dev/null 2>&1; then
            figlet "Maintenance" | lolcat
        else
            figlet "Maintenance"
        fi

    else

        echo
        echo "============================================================"
        echo "                 DEBIAN MAINTENANCE CENTER"
        echo "============================================================"

    fi

    echo
    echo -e "${CYAN}User:${RESET}       $REAL_USER"
    echo -e "${CYAN}Hostname:${RESET}   $(hostname)"
    echo -e "${CYAN}Kernel:${RESET}     $(uname -r)"
    echo

    ROOT_USE=$(df / | awk 'NR==2 {print $5}')

    echo -e "${CYAN}Root usage:${RESET} $ROOT_USE"
    echo

}

# ============================================================
# QUICK CLEAN
# ============================================================

quick_clean() {

    clear
    header "QUICK SYSTEM CLEAN"

    echo "This performs:"
    echo
    echo "  • APT cache cleanup"
    echo "  • Unused package cleanup"
    echo "  • Journal cleanup"
    echo "  • Temporary file cleanup"
    echo "  • User trash cleanup"
    echo "  • pip cache cleanup"
    echo

    if ! yes_no "Continue with quick cleanup?"; then
        return
    fi

    echo

    status "Removing unused packages..."
    apt-get autoremove --purge -y

    echo

    status "Cleaning APT package cache..."
    apt-get clean

    echo

    status "Reducing journal size..."
    journalctl --vacuum-size=50M

    echo

    if command -v systemd-tmpfiles >/dev/null 2>&1; then
        status "Cleaning expired temporary files..."
        systemd-tmpfiles --clean
    fi

    echo

    if command -v gio >/dev/null 2>&1; then
        status "Emptying user trash..."

        sudo -u "$REAL_USER" \
            HOME="$REAL_HOME" \
            gio trash --empty
    fi

    echo

    if command -v pip3 >/dev/null 2>&1; then

        status "Cleaning pip cache..."

        sudo -u "$REAL_USER" \
            HOME="$REAL_HOME" \
            pip3 cache purge || true

    fi

    echo
    success "Quick cleanup complete."

    echo
    df -h /

    pause
}

# ============================================================
# FULL CLEAN
# ============================================================

full_clean() {

    clear
    header "FULL SYSTEM CLEAN"

    echo "This performs the quick cleanup plus:"
    echo
    echo "  • Package list update"
    echo "  • System upgrade"
    echo "  • Residual configuration cleanup"
    echo "  • Editor backup scan"
    echo "  • Optional swap cycle"
    echo

    if ! yes_no "Continue with full cleanup?"; then
        return
    fi

    # --------------------------------------------------------
    # Update
    # --------------------------------------------------------

    header "PACKAGE UPDATE"

    apt-get update

    echo

    apt-get upgrade -y

    # --------------------------------------------------------
    # Autoremove
    # --------------------------------------------------------

    header "PACKAGE CLEANUP"

    apt-get autoremove --purge -y

    apt-get clean

    # --------------------------------------------------------
    # Residual packages
    # --------------------------------------------------------

    header "RESIDUAL CONFIGURATIONS"

    RC_PACKAGES=$(dpkg -l \
        | awk '$1 == "rc" {print $2}')

    if [[ -n "$RC_PACKAGES" ]]; then

        echo "Residual package configurations:"
        echo
        echo "$RC_PACKAGES"
        echo

        if yes_no "Purge these residual configurations?"; then

            while IFS= read -r package; do

                [[ -z "$package" ]] && continue

                status "Purging $package"

                dpkg --purge "$package"

            done <<< "$RC_PACKAGES"

        fi

    else

        success "No residual package configurations found."

    fi

    # --------------------------------------------------------
    # Journal
    # --------------------------------------------------------

    header "LOG CLEANUP"

    journalctl --vacuum-size=50M

    logrotate -f /etc/logrotate.conf

    # --------------------------------------------------------
    # Temporary files
    # --------------------------------------------------------

    header "TEMPORARY FILES"

    if command -v systemd-tmpfiles >/dev/null 2>&1; then

        systemd-tmpfiles --clean

    fi

    # --------------------------------------------------------
    # User trash
    # --------------------------------------------------------

    header "USER TRASH"

    if command -v gio >/dev/null 2>&1; then

        sudo -u "$REAL_USER" \
            HOME="$REAL_HOME" \
            gio trash --empty

    fi

    # --------------------------------------------------------
    # Pip cache
    # --------------------------------------------------------

    header "PYTHON CACHE"

    if command -v pip3 >/dev/null 2>&1; then

        sudo -u "$REAL_USER" \
            HOME="$REAL_HOME" \
            pip3 cache purge || true

    fi

    # --------------------------------------------------------
    # Editor backup files
    # --------------------------------------------------------

    header "EDITOR BACKUP FILES"

    BACKUP_LIST=$(mktemp)

    status "Scanning for editor backup files..."

    find "$REAL_HOME" \
        -xdev \
        -type f \
        -name '*~' \
        -print0 \
        > "$BACKUP_LIST" \
        2>/dev/null &

    FIND_PID=$!

    spinner \
        "$FIND_PID" \
        "Scanning for editor backup files"

    wait "$FIND_PID"

    BACKUP_COUNT=$(tr -cd '\0' < "$BACKUP_LIST" | wc -c)

    echo

    if (( BACKUP_COUNT > 0 )); then

        echo "Found $BACKUP_COUNT editor backup file(s)."
        echo

        if yes_no "Delete them?"; then

            DELETED=0

            while IFS= read -r -d '' file; do

                rm -f -- "$file"

                DELETED=$((DELETED + 1))

                PERCENT=$((DELETED * 100 / BACKUP_COUNT))

                printf "\rDeleting: %3d%% (%d/%d)" \
                    "$PERCENT" \
                    "$DELETED" \
                    "$BACKUP_COUNT"

            done < "$BACKUP_LIST"

            echo
            success "$DELETED backup file(s) removed."

        fi

    else

        success "No editor backup files found."

    fi

    rm -f "$BACKUP_LIST"

    # --------------------------------------------------------
    # Swap
    # --------------------------------------------------------

    header "SWAP"

    if swapon --show | grep -q .; then

        swapon --show

        echo

        if yes_no "Cycle swap memory?"; then

            FREE_RAM_KB=$(awk \
                '/MemAvailable:/ {print $2}' \
                /proc/meminfo)

            FREE_RAM_BYTES=$((FREE_RAM_KB * 1024))

            SWAP_USED_BYTES=$(swapon \
                --show \
                --bytes \
                --noheadings \
                --output=USED \
                | awk '{sum += $1} END {print sum+0}')

            if (( SWAP_USED_BYTES < FREE_RAM_BYTES )); then

                swapoff -a && swapon -a

                success "Swap cycled."

            else

                warning "Not enough available RAM to safely cycle swap."

            fi

        fi

    fi

    echo
    success "Full cleanup complete."

    echo
    df -h /

    pause
}

# ============================================================
# DISK AUDIT
# ============================================================

disk_audit() {

    clear
    header "DISK ANALYSIS"

    if [[ ! -f "$AUDIT_SCRIPT" ]]; then

        error "Disk audit script not found:"
        echo
        echo "    $AUDIT_SCRIPT"
        echo
        pause
        return

    fi

    if [[ ! -x "$AUDIT_SCRIPT" ]]; then
        chmod +x "$AUDIT_SCRIPT"
    fi

    "$AUDIT_SCRIPT"

    pause
}

# ============================================================
# UPDATE ONLY
# ============================================================

update_only() {

    clear
    header "SYSTEM UPDATE"

    echo "This will:"
    echo
    echo "  • Update package lists"
    echo "  • Install available upgrades"
    echo
    echo "No cleanup operations will be performed."
    echo

    if ! yes_no "Continue?"; then
        return
    fi

    echo

    apt-get update

    echo

    apt-get upgrade -y

    echo

    success "System update complete."

    pause
}

# ============================================================
# REPORT VIEWER
# ============================================================

view_reports() {

    clear
    header "SYSTEM REPORTS"

    mapfile -t REPORTS < <(
        find "$REPORT_DIR" \
            -maxdepth 1 \
            -type f \
            -name '*.txt' \
            -printf '%T@ %p\n' \
            2>/dev/null \
            | sort -nr \
            | cut -d' ' -f2-
    )

    if (( ${#REPORTS[@]} == 0 )); then

        warning "No saved reports found."

        pause
        return

    fi

    echo "Available reports:"
    echo

    for i in "${!REPORTS[@]}"; do

        FILE="${REPORTS[$i]}"

        printf "%2d) %s\n" \
            "$((i + 1))" \
            "$(basename "$FILE")"

    done

    echo
    echo " 0) Return"
    echo

    read -rp "Choose a report: " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] &&
       (( choice >= 1 && choice <= ${#REPORTS[@]} )); then

        FILE="${REPORTS[$((choice - 1))]}"

        clear

        if command -v less >/dev/null 2>&1; then
            less "$FILE"
        else
            cat "$FILE"
        fi

    else

        warning "Invalid selection."
        sleep 1

    fi
}

# ============================================================
# MAIN MENU
# ============================================================

while true; do

    show_banner

    echo -e "${WHITE}Choose a maintenance task:${RESET}"
    echo

    echo "  1) Quick System Clean"
    echo "  2) Full System Clean"
    echo "  3) Analyze Disk Usage"
    echo "  4) Update System Only"
    echo "  5) View Previous Reports"
    echo "  6) Exit"

    echo

    read -rp "Selection: " choice

    case "$choice" in

        1)
            quick_clean
            ;;

        2)
            full_clean
            ;;

        3)
            disk_audit
            ;;

        4)
            update_only
            ;;

        5)
            view_reports
            ;;

        6)
            clear
            echo
            echo -e "${GREEN}Goodbye, $REAL_USER.${RESET}"
            echo
            exit 0
            ;;

        *)
            warning "Invalid selection."
            sleep 1
            ;;

    esac

done
