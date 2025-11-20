#!/bin/bash
#
# Build Proxmox Chainguard Support Package
# Creates a distributable tar.gz package
#
# Usage: ./build-package.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version info
VERSION="3.0"
DATE=$(date +%Y%m%d)

# Package details
PACKAGE_NAME="proxmox-chainguard-support"
PACKAGE_DIR="${PACKAGE_NAME}"
ARCHIVE_NAME="${PACKAGE_NAME}.tar.gz"

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

# Main function
main() {
    print_header "Proxmox Chainguard Support Package Builder"
    echo ""
    print_info "Version: $VERSION"
    print_info "Date: $DATE"
    echo ""

    # Check if required files exist
    print_info "Checking required files..."

    REQUIRED_FILES=(
        "Chainguard.pm"
        "install-chainguard-support.sh"
        "uninstall-chainguard-support.sh"
        "README.md"
    )

    for file in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Missing required file: $file"
            exit 1
        fi
        print_success "Found: $file"
    done

    echo ""

    # Clean up old package directory and archive if they exist
    if [[ -d "$PACKAGE_DIR" ]]; then
        print_warning "Removing existing package directory..."
        rm -rf "$PACKAGE_DIR"
    fi

    if [[ -f "$ARCHIVE_NAME" ]]; then
        print_warning "Removing existing archive..."
        rm -f "$ARCHIVE_NAME"
    fi

    echo ""

    # Create package directory
    print_info "Creating package directory..."
    mkdir -p "$PACKAGE_DIR"
    print_success "Created $PACKAGE_DIR/"

    # Copy files to package directory
    print_info "Copying files to package directory..."

    cp Chainguard.pm "$PACKAGE_DIR/"
    print_success "Copied Chainguard.pm"

    cp install-chainguard-support.sh "$PACKAGE_DIR/"
    print_success "Copied install-chainguard-support.sh"

    cp uninstall-chainguard-support.sh "$PACKAGE_DIR/"
    print_success "Copied uninstall-chainguard-support.sh"

    cp README.md "$PACKAGE_DIR/"
    print_success "Copied README.md"

    # Set executable permissions on scripts
    chmod +x "$PACKAGE_DIR/install-chainguard-support.sh"
    chmod +x "$PACKAGE_DIR/uninstall-chainguard-support.sh"
    print_success "Set executable permissions on scripts"

    echo ""

    # Create archive
    print_info "Creating tar.gz archive..."
    tar -czf "$ARCHIVE_NAME" "$PACKAGE_DIR"
    print_success "Created $ARCHIVE_NAME"

    # Calculate checksums
    echo ""
    print_info "Calculating checksums..."

    if command -v md5 &> /dev/null; then
        MD5=$(md5 -q "$ARCHIVE_NAME")
    elif command -v md5sum &> /dev/null; then
        MD5=$(md5sum "$ARCHIVE_NAME" | awk '{print $1}')
    else
        MD5="(md5 command not found)"
    fi

    if command -v sha256sum &> /dev/null; then
        SHA256=$(sha256sum "$ARCHIVE_NAME" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        SHA256=$(shasum -a 256 "$ARCHIVE_NAME" | awk '{print $1}')
    else
        SHA256="(sha256sum command not found)"
    fi

    # Get file size
    if [[ "$OSTYPE" == "darwin"* ]]; then
        SIZE=$(ls -lh "$ARCHIVE_NAME" | awk '{print $5}')
    else
        SIZE=$(ls -lh "$ARCHIVE_NAME" | awk '{print $5}')
    fi

    # Clean up package directory
    print_info "Cleaning up temporary files..."
    rm -rf "$PACKAGE_DIR"
    print_success "Removed temporary directory"

    echo ""
    print_header "Build Complete!"
    echo ""

    # Display package information
    print_info "Package Information:"
    echo ""
    echo "  Name:    $ARCHIVE_NAME"
    echo "  Size:    $SIZE"
    echo "  Version: $VERSION"
    echo "  Date:    $DATE"
    echo ""
    echo "  MD5:     $MD5"
    echo "  SHA256:  $SHA256"
    echo ""

    # Display contents
    print_info "Package Contents:"
    tar -tzf "$ARCHIVE_NAME" | sed 's/^/  /'
    echo ""

    # Display usage instructions
    print_header "Usage Instructions"
    echo ""
    print_info "To install on Proxmox:"
    echo ""
    echo "  # Extract the archive"
    echo "  tar -xzf $ARCHIVE_NAME"
    echo "  cd $PACKAGE_NAME"
    echo ""
    echo "  # Run the installer"
    echo "  chmod +x install-chainguard-support.sh"
    echo "  sudo ./install-chainguard-support.sh"
    echo ""

    print_info "To distribute:"
    echo ""
    echo "  # Upload to file sharing service"
    echo "  scp $ARCHIVE_NAME user@server:path/"
    echo ""
    echo "  # Or share checksums for verification:"
    echo "  MD5:    $MD5"
    echo "  SHA256: $SHA256"
    echo ""

    print_success "Package ready for distribution!"
}

# Run main function
main
