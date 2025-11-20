#!/bin/bash
#
# Proxmox Chainguard OS Support Uninstaller
# Removes Chainguard OS support from Proxmox VE LXC containers
#
# Usage: sudo ./uninstall-chainguard-support.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SETUP_PM="/usr/share/perl5/PVE/LXC/Setup.pm"
CONFIG_PM="/usr/share/perl5/PVE/LXC/Config.pm"
SETUP_DIR="/usr/share/perl5/PVE/LXC/Setup"
CHAINGUARD_PM="${SETUP_DIR}/Chainguard.pm"

# Functions
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

check_installed() {
    print_info "Checking if Chainguard support is installed..."

    local found=0

    if [[ -f "$CHAINGUARD_PM" ]]; then
        print_success "Found Chainguard.pm"
        found=1
    else
        print_warning "Chainguard.pm not found"
    fi

    if grep -q "chainguard.*PVE::LXC::Setup::Chainguard" "$SETUP_PM" 2>/dev/null; then
        print_success "Found Chainguard in Setup.pm"
        found=1
    else
        print_warning "Chainguard not found in Setup.pm"
    fi

    if [[ $found -eq 0 ]]; then
        print_error "Chainguard support does not appear to be installed"
        exit 1
    fi
}

check_containers() {
    print_info "Checking for running Chainguard containers..."

    if command -v pct &> /dev/null; then
        local chainguard_containers=$(pct list 2>/dev/null | awk '{print $1}' | tail -n +2 | while read vmid; do
            if pct config "$vmid" 2>/dev/null | grep -q "ostype: chainguard"; then
                echo "$vmid"
            fi
        done)

        if [[ -n "$chainguard_containers" ]]; then
            print_warning "Found Chainguard containers:"
            echo "$chainguard_containers" | while read vmid; do
                local status=$(pct status "$vmid" 2>/dev/null | awk '{print $2}')
                echo "  - CT $vmid ($status)"
            done
            echo ""
            print_warning "These containers will revert to 'unmanaged' type"
            read -p "Do you want to continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Uninstallation cancelled"
                exit 0
            fi
        else
            print_success "No Chainguard containers found"
        fi
    fi
}

find_backups() {
    print_info "Looking for backup files..."

    local backups=$(find "$(dirname "$SETUP_PM")" -name "Setup.pm.chainguard-backup-*" 2>/dev/null | sort -r)

    if [[ -n "$backups" ]]; then
        print_success "Found backup files:"
        echo "$backups" | nl
        echo ""
        read -p "Do you want to restore from a backup? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            read -p "Enter backup number to restore (or 0 to skip): " backup_num
            if [[ "$backup_num" =~ ^[1-9][0-9]*$ ]]; then
                local selected_backup=$(echo "$backups" | sed -n "${backup_num}p")
                if [[ -f "$selected_backup" ]]; then
                    return 0
                else
                    print_error "Invalid backup selection"
                    return 1
                fi
            fi
        fi
    else
        print_warning "No backup files found"
    fi

    return 1
}

restore_from_backup() {
    local backup_file="$1"

    print_info "Restoring from backup: $(basename "$backup_file")"

    cp "$backup_file" "$SETUP_PM"
    print_success "Restored Setup.pm from backup"
}

manual_removal() {
    print_info "Performing manual removal..."

    # Create backups before removing
    local backup_suffix=".pre-uninstall-backup-$(date +%Y%m%d-%H%M%S)"
    cp "$SETUP_PM" "${SETUP_PM}${backup_suffix}"
    print_success "Created backup: ${SETUP_PM}${backup_suffix}"

    cp "$CONFIG_PM" "${CONFIG_PM}${backup_suffix}"
    print_success "Created backup: ${CONFIG_PM}${backup_suffix}"

    # Remove Chainguard import from Setup.pm
    if grep -q "use PVE::LXC::Setup::Chainguard" "$SETUP_PM"; then
        sed -i.bak '/use PVE::LXC::Setup::Chainguard;/d' "$SETUP_PM"
        print_success "Removed Chainguard import from Setup.pm"
    fi

    # Remove Chainguard from plugins hash
    if grep -q "chainguard.*PVE::LXC::Setup::Chainguard" "$SETUP_PM"; then
        sed -i.bak '/chainguard.*PVE::LXC::Setup::Chainguard/d' "$SETUP_PM"
        print_success "Removed Chainguard from plugins registry"
    fi

    # Remove chainguard from Config.pm ostype enum
    if grep -q "alpine chainguard gentoo" "$CONFIG_PM"; then
        sed -i.bak 's/alpine chainguard gentoo/alpine gentoo/' "$CONFIG_PM"
        print_success "Removed chainguard from ostype enumeration"
    fi

    # Clean up sed backups
    rm -f "${SETUP_PM}.bak" "${CONFIG_PM}.bak"
}

remove_module() {
    print_info "Removing Chainguard.pm module..."

    if [[ -f "$CHAINGUARD_PM" ]]; then
        # Create a backup
        local backup_file="${CHAINGUARD_PM}.removed-$(date +%Y%m%d-%H%M%S)"
        mv "$CHAINGUARD_PM" "$backup_file"
        print_success "Moved Chainguard.pm to $backup_file"
    else
        print_warning "Chainguard.pm not found"
    fi
}

restart_services() {
    print_info "Restarting Proxmox services..."

    systemctl restart pvedaemon.service
    print_success "Restarted pvedaemon"

    systemctl restart pveproxy.service
    print_success "Restarted pveproxy"
}

verify_removal() {
    print_info "Verifying removal..."

    local errors=0

    if [[ -f "$CHAINGUARD_PM" ]]; then
        print_warning "Chainguard.pm still exists"
        errors=$((errors + 1))
    else
        print_success "Chainguard.pm removed"
    fi

    if grep -q "chainguard.*PVE::LXC::Setup::Chainguard" "$SETUP_PM" 2>/dev/null; then
        print_warning "Setup.pm still contains Chainguard references"
        errors=$((errors + 1))
    else
        print_success "Setup.pm cleaned"
    fi

    if [[ $errors -gt 0 ]]; then
        print_warning "Removal completed with warnings"
        return 1
    else
        print_success "Removal verified successfully"
        return 0
    fi
}

print_summary() {
    echo ""
    print_header "Uninstallation Complete!"
    echo ""
    print_success "Chainguard OS support has been removed from Proxmox VE"
    echo ""
    print_info "Backup files have been created and can be found in:"
    echo "  - $(dirname "$SETUP_PM")"
    echo ""
    print_warning "Existing Chainguard containers will now be 'unmanaged' type"
    print_info "These containers will continue to run but without Proxmox configuration support"
    echo ""
    print_info "To reinstall, run: ./install-chainguard-support.sh"
    echo ""
}

# Main uninstallation flow
main() {
    print_header "Proxmox Chainguard OS Support Uninstaller"
    echo ""

    # Pre-flight checks
    check_root
    check_installed
    check_containers

    echo ""
    print_header "Uninstalling Chainguard Support"
    echo ""

    # Try to restore from backup, otherwise manual removal
    if find_backups; then
        local backups=$(find "$(dirname "$SETUP_PM")" -name "Setup.pm.chainguard-backup-*" 2>/dev/null | sort -r)
        local backup_num
        read -p "Enter backup number: " backup_num
        local selected_backup=$(echo "$backups" | sed -n "${backup_num}p")
        if [[ -f "$selected_backup" ]]; then
            restore_from_backup "$selected_backup"
        else
            print_error "Invalid selection, falling back to manual removal"
            manual_removal
        fi
    else
        manual_removal
    fi

    # Remove the module file
    remove_module

    # Restart services
    restart_services

    # Verify
    verify_removal

    # Success
    print_summary
}

# Run main function
main

exit 0
