# Chainguard OS Support for Proxmox VE LXC

Native Chainguard OS support patch for Proxmox VE, enabling full integration of Chainguard containers with proper OS recognition, networking, and system configuration.

**Version**: 3.0
**Date**: 2025-11-20
**Tested on**: Proxmox VE 9.1.1

---

## Overview

This patch adds native Chainguard OS support to Proxmox VE, allowing you to create and manage both traditional Chainguard LXC containers and OCI container images:

### Traditional LXC Templates (with systemd)
- ✅ Proper OS recognition (`ostype: chainguard`)
- ✅ DHCP and static IP networking via systemd-networkd
- ✅ DNS configuration via systemd-resolved
- ✅ Password and SSH key authentication
- ✅ SSH server enablement (when present)
- ✅ cgroupv2 support
- ✅ Full systemd integration

### OCI Container Images (Chainguard & Wolfi)
- ✅ Wolfi and Chainguard OCI image support
- ✅ Automatic entrypoint detection and execution
- ✅ Host-managed networking (DHCP)
- ✅ Environment variable injection
- ✅ Single-process container mode
- ✅ Compatible with Chainguard and Wolfi minimal images

---

## What Gets Installed

The installer modifies three Proxmox files:

1. **`/usr/share/perl5/PVE/LXC/Setup.pm`**
   - Adds `use PVE::LXC::Setup::Chainguard;` import
   - Registers Chainguard plugin in plugins hash
   - Adds `wolfi => 'chainguard'` alias for Wolfi OS

2. **`/usr/share/perl5/PVE/LXC/Config.pm`**
   - Adds `chainguard` to ostype enumeration

3. **`/usr/share/perl5/PVE/LXC/Setup/Chainguard.pm`** (NEW)
   - Complete plugin module with systemd-based configuration for LXC templates
   - OCI-aware mode for minimal container images
   - Automatic detection of OCI vs traditional LXC containers

All original files are backed up with timestamps before modification.

---

## Quick Start

### 1. Installation

```bash
# Extract the patch
tar -xzf proxmox-chainguard-support.tar.gz
cd proxmox-chainguard-support

# Run the installer
chmod +x install-chainguard-support.sh
sudo ./install-chainguard-support.sh
```

The installer will:
- ✅ Validate your Proxmox environment
- ✅ Check for existing installations
- ✅ Create timestamped backups
- ✅ Install the Chainguard plugin module
- ✅ Patch Setup.pm and Config.pm
- ✅ Restart Proxmox services
- ✅ Verify the installation

### 2. Create a Container

**With DHCP:**
```bash
pct create 100 local:vztmpl/chainguard-*.tar.zst \
  --hostname my-chainguard \
  --memory 1024 \
  --cores 2 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --storage local-lvm \
  --unprivileged 1 \
  --password
```

**With Static IP:**
```bash
pct create 101 local:vztmpl/chainguard-*.tar.zst \
  --hostname my-chainguard \
  --memory 1024 \
  --cores 2 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.100/24,gw=192.168.1.1 \
  --storage local-lvm \
  --unprivileged 1 \
  --password
```

**With SSH Keys:**
```bash
pct create 102 local:vztmpl/chainguard-*.tar.zst \
  --hostname my-chainguard \
  --memory 1024 \
  --cores 2 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --storage local-lvm \
  --unprivileged 1 \
  --ssh-public-keys ~/.ssh/id_rsa.pub
```

### 3. Using OCI Container Images

The patch also supports Chainguard and Wolfi OCI container images:

```bash
# Create from Chainguard/Wolfi OCI image
pct create 200 local:vztmpl/nginx_latest.tar \
  --hostname nginx \
  --memory 512 \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --storage local-lvm \
  --unprivileged 1

# Start the container (runs the OCI entrypoint automatically)
pct start 200
```

**Note:** OCI images use host-managed networking and run their defined entrypoint as PID 1. They don't require systemd and work with minimal Wolfi/Chainguard images.

### 4. Start and Access

```bash
# Start the container
pct start 100

# Console access (no SSH needed)
pct console 100

# Execute commands
pct exec 100 -- python3 --version
```

---

## Files Included

- **Chainguard.pm** - Plugin module with full systemd support
- **install-chainguard-support.sh** - Automated installer with validation
- **uninstall-chainguard-support.sh** - Automated uninstaller with rollback
- **README.md** - This documentation
- **build-package.sh** - Script to create distribution tarball

---

## Requirements

- Proxmox VE 8.0 or later (tested on 9.0.11)
- Root access to Proxmox host
- Chainguard container image with systemd
- Perl 5.x (included with Proxmox)

---

## Features

### Network Configuration

**DHCP Networking:**
- Automatic IP assignment via systemd-networkd
- Network config file created: `/etc/systemd/network/10-eth0.network`
- Content example:
  ```
  [Match]
  Name=eth0

  [Network]
  DHCP=yes
  ```

**Static IP Networking:**
- Manual IPv4/IPv6 configuration
- Gateway and route configuration
- Network config example:
  ```
  [Match]
  Name=eth0

  [Network]
  Address=192.168.1.100/24
  Gateway=192.168.1.1
  ```

### DNS Configuration

- Configured via systemd-resolved
- Configuration file: `/etc/systemd/resolved.conf.d/pve.conf`
- Supports custom nameservers and search domains

### System Integration

- **Init System**: Full systemd support
- **Device Management**: Automatic via systemd-udevd
- **Console**: Handled by getty@.service with automatic securetty configuration
- **cgroupv2**: Enabled for modern resource management
- **SSH**: Automatically enables sshd.service if present

### Authentication

- **Passwords**: Set during creation with `--password` flag
- **SSH Keys**: Add during creation with `--ssh-public-keys` flag
- **Console**: Always available via `pct console <VMID>` (pts/1 automatically added to securetty)

---

## Testing Results

Fully tested on Proxmox VE 9.0.11 with Chainguard Python 3.13 containers:

| Test | Result | Details |
|------|--------|---------|
| Container Creation | ✅ | Created with `ostype: chainguard` |
| DHCP Networking | ✅ | IP: 192.168.2.122/24, internet verified |
| Static IP | ✅ | IP: 192.168.2.91/24, gateway configured |
| Password Auth | ✅ | Hash verified in `/etc/shadow` |
| SSH Key Auth | ✅ | Key added to `authorized_keys` |
| Python 3.13.9 | ✅ | Fully functional |
| Internet Access | ✅ | ping 8.8.8.8 successful |

---

## Advanced Usage

### Setting Passwords

**During creation:**
```bash
pct create <VMID> ... --password
# You'll be prompted to enter the password
```

**After creation:**
```bash
pct exec <VMID> -- bash -c 'echo "root:yourpassword" | chpasswd'
```

### Accessing Containers

**Console (always works):**
```bash
pct console <VMID>
```

**Direct command execution:**
```bash
pct exec <VMID> -- <command>
pct exec <VMID> -- python3 --version
pct exec <VMID> -- ip addr show
```

**SSH (if sshd is installed):**
```bash
# Get container IP
pct exec <VMID> -- ip addr show eth0 | grep inet

# SSH to container
ssh root@<container-ip>
```

### Checking Network Configuration

```bash
# View network config file
pct exec <VMID> -- cat /etc/systemd/network/10-eth0.network

# Check networkd status
pct exec <VMID> -- systemctl status systemd-networkd

# Check IP address
pct exec <VMID> -- ip addr show eth0
```

---

## Uninstallation

```bash
cd proxmox-chainguard-support
sudo ./uninstall-chainguard-support.sh
```

The uninstaller will:
- Check for running Chainguard containers
- Offer to restore from backups
- Remove all modifications
- Restart Proxmox services

**Note**: Existing Chainguard containers will continue to run but will be marked as "unmanaged" type after uninstallation.

---

## Backup & Rollback

### Automatic Backups

The installer creates timestamped backups:
```
/usr/share/perl5/PVE/LXC/Setup.pm.chainguard-backup-YYYYMMDD-HHMMSS
/usr/share/perl5/PVE/LXC/Config.pm.chainguard-backup-YYYYMMDD-HHMMSS
```

### Manual Rollback

```bash
cd /usr/share/perl5/PVE/LXC

# List backups
ls -lt Setup.pm.chainguard-backup-* | head -5

# Restore from backup
cp Setup.pm.chainguard-backup-YYYYMMDD-HHMMSS Setup.pm
cp Config.pm.chainguard-backup-YYYYMMDD-HHMMSS Config.pm

# Remove Chainguard module
rm Setup/Chainguard.pm

# Restart services
systemctl restart pvedaemon pveproxy
```

---

## Troubleshooting

### Container Creation Fails

**Check task logs:**
```bash
tail -f /var/log/pve/tasks/*.log
```

**Common issues:**
- Missing device nodes → Use `fix-lxc` tool to remove them
- Wrong ostype → Verify `ostype: chainguard` in config
- Network issues → Check systemd-networkd status

### Network Not Working

**Check systemd-networkd:**
```bash
pct exec <VMID> -- systemctl status systemd-networkd
```

**View network config:**
```bash
pct exec <VMID> -- cat /etc/systemd/network/10-eth0.network
```

**Check interface:**
```bash
pct exec <VMID> -- ip addr show eth0
```

**Restart networking:**
```bash
pct exec <VMID> -- systemctl restart systemd-networkd
```

### SSH Not Available

Most minimal Chainguard images don't include SSH server by default.

**Alternatives:**
- Use `pct console <VMID>` for console access
- Use `pct exec <VMID> -- <command>` to run commands
- Install openssh-server if APK repositories are configured

### Installation Fails

**Check Proxmox version:**
```bash
pveversion
```

**Check Perl syntax:**
```bash
perl -c /usr/share/perl5/PVE/LXC/Setup/Chainguard.pm
```

**Check for conflicts:**
```bash
grep -i chainguard /usr/share/perl5/PVE/LXC/Setup.pm
```

---

## Technical Details

### Plugin Architecture

Proxmox uses a plugin system for OS-specific container setup. Each OS has:
- A module in `/usr/share/perl5/PVE/LXC/Setup/<OSName>.pm`
- Registration in `Setup.pm` plugins hash
- Entry in `Config.pm` ostype enumeration

### Key Implementation Details

**Network Setup:**
- Called in `post_create_hook()` during container creation
- Creates `/etc/systemd/network/10-<interface>.network` files
- Enables systemd-networkd.service and systemd-resolved.service

**DHCP Detection:**
- Checks if `$d->{ip} eq 'dhcp'` in parsed network config
- Creates config with `DHCP=yes`

**Static IP Detection:**
- Checks if `$ip =~ m|/|` (contains CIDR notation)
- Extracts address and gateway from parsed config

**SSH Enablement:**
- Checks for sshd.service or ssh.service in `/usr/lib/systemd/system/`
- Creates symlink in `/etc/systemd/system/multi-user.target.wants/`

---

## Known Limitations

- Requires one-time Proxmox modification (not a standard package)
- Proxmox updates may require reinstalling the patch
- Minimal Chainguard/Wolfi OCI images may not include SSH server or standard utilities
- OCI containers use host-managed networking (no internal network configuration)

---

## Contributing to Proxmox

This implementation is ready for upstream contribution:

**Proxmox pve-container repository:**
- Git: https://git.proxmox.com/git/pve-container.git
- Mailing list: pve-devel@lists.proxmox.com
- Forum: https://forum.proxmox.com/

**Files to submit:**
- `Chainguard.pm` - Plugin module
- Patch for `Setup.pm` - Import and plugin registration
- Patch for `Config.pm` - ostype enumeration
- Test results and documentation

---

## Building Distribution Package

```bash
./build-package.sh
```

This creates `proxmox-chainguard-support.tar.gz` with:
- Chainguard.pm module
- Install/uninstall scripts
- Complete documentation

---

## Support & Resources

**Documentation:**
- Proxmox LXC: https://pve.proxmox.com/wiki/Linux_Container
- Chainguard: https://chainguard.dev/
- systemd-networkd: https://www.freedesktop.org/software/systemd/man/systemd-networkd.html

**Logs:**
- Proxmox tasks: `/var/log/pve/tasks/*.log`
- Container logs: `journalctl -M <container-name>`
- System logs: `/var/log/syslog`

**Community:**
- Proxmox Forum: https://forum.proxmox.com/
- Chainguard Community: https://chainguard.dev/
- Reddit: r/Proxmox

---

## Changelog

**Version 3.0 (2025-11-20)**
- ✅ **OCI Container Support** - Full support for Chainguard and Wolfi OCI images
- ✅ Added `wolfi => 'chainguard'` alias for Wolfi OS detection
- ✅ OCI-aware mode: automatic detection of OCI vs traditional LXC containers
- ✅ Host-managed networking for OCI containers
- ✅ Skips systemd requirements for minimal OCI images
- ✅ Tested with Chainguard nginx and postgres OCI images
- ✅ Updated installer to add wolfi alias automatically

**Version 2.0 (2025-11-18)**
- ✅ Full implementation with working DHCP and static IP
- ✅ Fixed network configuration in post_create_hook
- ✅ Added Config.pm patching for ostype enum
- ✅ Comprehensive testing on Proxmox 9.1.1
- ✅ Production-ready release

**Version 1.0 (2025-11-18)**
- Initial implementation
- Basic Chainguard OS detection
- systemd-networkd integration
