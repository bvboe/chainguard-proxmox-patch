#!/bin/bash
#
# Proxmox Chainguard OS Support Installer
# Adds native Chainguard OS support to Proxmox VE LXC containers
#
# Usage: sudo ./install-chainguard-support.sh
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
BACKUP_SUFFIX=".chainguard-backup-$(date +%Y%m%d-%H%M%S)"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

check_proxmox() {
    print_info "Checking Proxmox VE installation..."

    if [[ ! -f /etc/pve/.version ]]; then
        print_error "Proxmox VE not detected"
        print_info "This script is designed for Proxmox VE systems"
        exit 1
    fi

    local pve_version=$(pveversion | head -n1)
    print_success "Proxmox VE detected: $pve_version"
}

check_files() {
    print_info "Checking required files..."

    if [[ ! -f "$SETUP_PM" ]]; then
        print_error "Setup.pm not found at $SETUP_PM"
        exit 1
    fi
    print_success "Found Setup.pm"

    if [[ ! -f "$CONFIG_PM" ]]; then
        print_error "Config.pm not found at $CONFIG_PM"
        exit 1
    fi
    print_success "Found Config.pm"

    if [[ ! -d "$SETUP_DIR" ]]; then
        print_error "Setup directory not found at $SETUP_DIR"
        exit 1
    fi
    print_success "Found Setup directory"

    if [[ ! -f "$SCRIPT_DIR/Chainguard.pm" ]]; then
        print_error "Chainguard.pm not found in script directory"
        print_info "Expected: $SCRIPT_DIR/Chainguard.pm"
        exit 1
    fi
    print_success "Found Chainguard.pm module"
}

check_perl_syntax() {
    print_info "Validating Perl syntax..."

    if ! command -v perl &> /dev/null; then
        print_error "Perl not found"
        exit 1
    fi

    # Check Chainguard.pm syntax
    if ! perl -c "$SCRIPT_DIR/Chainguard.pm" &> /dev/null; then
        print_error "Chainguard.pm has syntax errors"
        perl -c "$SCRIPT_DIR/Chainguard.pm"
        exit 1
    fi
    print_success "Perl syntax validation passed"
}

check_already_installed() {
    print_info "Checking if Chainguard support is already installed..."

    if [[ -f "$CHAINGUARD_PM" ]]; then
        print_warning "Chainguard.pm already exists"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi

    if grep -q "chainguard.*PVE::LXC::Setup::Chainguard" "$SETUP_PM" 2>/dev/null; then
        print_warning "Setup.pm appears to already have Chainguard support"
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
}

create_backup() {
    print_info "Creating backups..."

    cp "$SETUP_PM" "${SETUP_PM}${BACKUP_SUFFIX}"
    print_success "Backed up Setup.pm to ${SETUP_PM}${BACKUP_SUFFIX}"

    cp "$CONFIG_PM" "${CONFIG_PM}${BACKUP_SUFFIX}"
    print_success "Backed up Config.pm to ${CONFIG_PM}${BACKUP_SUFFIX}"

    if [[ -f "$CHAINGUARD_PM" ]]; then
        cp "$CHAINGUARD_PM" "${CHAINGUARD_PM}${BACKUP_SUFFIX}"
        print_success "Backed up existing Chainguard.pm"
    fi
}

install_module() {
    print_info "Installing Chainguard.pm module..."

    cp "$SCRIPT_DIR/Chainguard.pm" "$CHAINGUARD_PM"
    chmod 644 "$CHAINGUARD_PM"
    chown root:root "$CHAINGUARD_PM"

    print_success "Installed Chainguard.pm to $CHAINGUARD_PM"
}

patch_setup_pm() {
    print_info "Patching Setup.pm..."

    # Add import statement
    if grep -q "use PVE::LXC::Setup::Chainguard" "$SETUP_PM"; then
        print_warning "Setup.pm already contains Chainguard import, skipping"
    else
        if grep -q "use PVE::LXC::Setup::Alpine" "$SETUP_PM"; then
            sed -i '/use PVE::LXC::Setup::Alpine;/a use PVE::LXC::Setup::Chainguard;' "$SETUP_PM"
            print_success "Added Chainguard import to Setup.pm"
        else
            print_error "Could not find Alpine import in Setup.pm"
            exit 1
        fi
    fi

    # Check if already patched
    if grep -q "chainguard.*PVE::LXC::Setup::Chainguard" "$SETUP_PM"; then
        print_warning "Setup.pm already contains Chainguard plugin entry, skipping"
    else
        # Add to plugins hash after alpine
        if grep -q "alpine.*PVE::LXC::Setup::Alpine" "$SETUP_PM"; then
            sed -i "/alpine => 'PVE::LXC::Setup::Alpine',/a \    chainguard => 'PVE::LXC::Setup::Chainguard'," "$SETUP_PM"
            print_success "Added Chainguard to plugins registry"
        else
            print_error "Could not find Alpine plugin in Setup.pm"
            exit 1
        fi
    fi

    # Add wolfi alias for OCI image support
    if grep -q "wolfi => 'chainguard'" "$SETUP_PM"; then
        print_warning "Setup.pm already contains wolfi alias, skipping"
    else
        if grep -q "almalinux => 'centos'," "$SETUP_PM"; then
            sed -i "/almalinux => 'centos',/a \    wolfi => 'chainguard'," "$SETUP_PM"
            print_success "Added wolfi to chainguard alias for OCI support"
        else
            print_error "Could not find alias hash in Setup.pm"
            exit 1
        fi
    fi
}

patch_config_pm() {
    print_info "Patching Config.pm..."

    # Check if already patched
    if grep -q "alpine chainguard gentoo" "$CONFIG_PM"; then
        print_warning "Config.pm already contains chainguard in ostype enum, skipping"
    else
        # Add chainguard to ostype enum after alpine
        if grep -q "qw(debian.*alpine.*gentoo.*nixos.*unmanaged)" "$CONFIG_PM"; then
            sed -i 's/alpine gentoo/alpine chainguard gentoo/' "$CONFIG_PM"
            print_success "Added chainguard to ostype enumeration"
        else
            print_error "Could not find ostype enum in Config.pm"
            print_info "You may need to manually add 'chainguard' to the ostype enum"
            exit 1
        fi
    fi
}

restart_services() {
    print_info "Restarting Proxmox services..."

    systemctl restart pvedaemon.service
    print_success "Restarted pvedaemon"

    systemctl restart pveproxy.service
    print_success "Restarted pveproxy"
}

verify_installation() {
    print_info "Verifying installation..."

    # Check if Chainguard.pm exists and has correct permissions
    if [[ -f "$CHAINGUARD_PM" ]]; then
        local perms=$(stat -c "%a" "$CHAINGUARD_PM" 2>/dev/null || stat -f "%A" "$CHAINGUARD_PM")
        if [[ "$perms" == "644" ]]; then
            print_success "Chainguard.pm installed with correct permissions"
        else
            print_warning "Chainguard.pm permissions are $perms (expected 644)"
        fi
    else
        print_error "Chainguard.pm not found after installation"
        exit 1
    fi

    # Check if Setup.pm contains our changes
    if grep -q "chainguard.*PVE::LXC::Setup::Chainguard" "$SETUP_PM"; then
        print_success "Setup.pm contains Chainguard plugin registration"
    else
        print_error "Setup.pm does not contain Chainguard plugin"
        exit 1
    fi

    # Check if Config.pm contains our changes
    if grep -q "alpine chainguard gentoo" "$CONFIG_PM"; then
        print_success "Config.pm contains chainguard in ostype enum"
    else
        print_error "Config.pm does not contain chainguard ostype"
        exit 1
    fi

    # Try to load the module
    if perl -I/usr/share/perl5 -MPVE::LXC::Setup::Chainguard -e 'print "OK\n"' &>/dev/null; then
        print_success "Chainguard module loads successfully"
    else
        print_warning "Could not verify Perl module loading (this may be normal)"
    fi
}

print_summary() {
    echo ""
    print_header "Installation Complete!"
    echo ""
    print_success "Chainguard OS support has been added to Proxmox VE"
    echo ""
    print_info "Backup files created:"
    echo "  - ${SETUP_PM}${BACKUP_SUFFIX}"
    echo "  - ${CONFIG_PM}${BACKUP_SUFFIX}"
    if [[ -f "${CHAINGUARD_PM}${BACKUP_SUFFIX}" ]]; then
        echo "  - ${CHAINGUARD_PM}${BACKUP_SUFFIX}"
    fi
    echo ""
    print_info "You can now create Chainguard LXC containers using:"
    echo "  pct create <VMID> local:vztmpl/chainguard-*.tar.zst ..."
    echo ""
    print_info "To uninstall, run: ./uninstall-chainguard-support.sh"
    echo ""
}

# Main installation flow
main() {
    print_header "Proxmox Chainguard OS Support Installer"
    echo ""

    # Pre-flight checks
    check_root
    check_proxmox
    check_files
    check_perl_syntax
    check_already_installed

    echo ""
    print_header "Installing Chainguard Support"
    echo ""

    # Installation steps
    create_backup
    install_module
    patch_setup_pm
    patch_config_pm
    restart_services
    verify_installation

    # Success
    print_summary
}

# Run main function
main

exit 0
