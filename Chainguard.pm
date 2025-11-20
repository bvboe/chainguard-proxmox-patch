package PVE::LXC::Setup::Chainguard;

use strict;
use warnings;

use PVE::LXC;
use PVE::LXC::Setup::Base;
use PVE::Network;
use PVE::Tools;
use File::Path;

use base qw(PVE::LXC::Setup::Base);

sub new {
    my ($class, $conf, $rootdir, $os_release) = @_;

    # Check if this is an OCI container (has entrypoint defined)
    my $is_oci_container = defined($conf->{entrypoint});

    # Only require systemd for traditional LXC templates
    if (!$is_oci_container) {
        die "systemd not found - Chainguard requires systemd\n"
            if ! -f "$rootdir/usr/lib/systemd/systemd" && ! -f "$rootdir/lib/systemd/systemd";
    }

    my $version = $os_release->{VERSION_ID} || "unknown";

    my $self = {
        conf => $conf,
        rootdir => $rootdir,
        version => $version,
        os_release => $os_release,
        is_oci => $is_oci_container,
    };

    $conf->{ostype} = "chainguard";

    return bless $self, $class;
}

sub devttydir {
    return "";
}

sub template_fixup {
    my ($self, $conf) = @_;

    # Chainguard uses systemd - no special fixup needed
    # systemd handles device management automatically
    # OCI containers don't need fixup either
}

sub setup_init {
    my ($self, $conf) = @_;

    # Chainguard uses systemd
    # systemd handles getty spawning automatically via getty@.service template
    # No manual inittab configuration needed
    # OCI containers use their entrypoint, not init
}

sub setup_network {
    my ($self, $conf) = @_;

    # Skip network setup for OCI containers - they use host-managed networking
    return if $self->{is_oci};

    # Parse network configuration from container config
    my $networks = {};
    foreach my $k (keys %$conf) {
        next if $k !~ m/^net(\d+)$/;
        my $ind = $1;
        my $d = PVE::LXC::Config->parse_lxc_network($conf->{$k});
        $networks->{$ind} = $d;
    }

    return if !scalar(keys %$networks);

    # Create systemd-networkd configuration for each interface
    foreach my $iface (sort keys %$networks) {
        my $d = $networks->{$iface};
        my $name = $d->{name};
        next if !$name;

        # Create systemd-networkd configuration file
        my $filename = "/etc/systemd/network/10-$name.network";
        my $content = "[Match]\nName=$name\n\n[Network]\n";

        # Parse IP configuration (from parsed network config)
        my $ip = $d->{ip};
        my $ip6 = $d->{ip6};

        # IPv4 configuration
        if (defined($ip) && $ip eq 'dhcp') {
            # DHCP
            $content .= "DHCP=yes\n";
        } elsif (defined($ip) && $ip ne 'manual' && $ip =~ m|/|) {
            # Static IPv4 address (has CIDR notation)
            $content .= "Address=$ip\n";
            if ($d->{gw}) {
                $content .= "Gateway=$d->{gw}\n";
            }
        }

        # IPv6 configuration
        if (defined($ip6) && $ip6 =~ m|:|) {
            # Static IPv6 address
            $content .= "Address=$ip6\n";
            if ($d->{gw6}) {
                $content .= "Gateway=$d->{gw6}\n";
            }
        } elsif (defined($ip6) && $ip6 =~ /^(auto|dhcp)$/) {
            # IPv6 auto or DHCP
            $content .= "DHCP=ipv6\n" if $ip6 eq 'dhcp';
        }

        # Write network configuration
        $self->ct_file_set_contents($filename, $content);
    }

    # Enable and link systemd-networkd service
    $self->ct_mkdir("/etc/systemd/system/multi-user.target.wants", 0755);
    $self->ct_symlink("/usr/lib/systemd/system/systemd-networkd.service",
                      "/etc/systemd/system/multi-user.target.wants/systemd-networkd.service");

    # Enable and link systemd-resolved service for DNS
    $self->ct_symlink("/usr/lib/systemd/system/systemd-resolved.service",
                      "/etc/systemd/system/multi-user.target.wants/systemd-resolved.service");
}

sub setup_systemd_networkd {
    my ($self) = @_;

    # Skip for OCI containers
    return if $self->{is_oci};

    # Ensure systemd-networkd directory exists
    $self->ct_mkdir("/etc/systemd/network", 0755);
}

sub setup_systemd_console {
    my ($self, $conf) = @_;

    # systemd handles console automatically via getty@.service
    # Nothing special needed for Chainguard
    # OCI containers don't need console setup
}

sub set_timezone {
    my ($self, $conf) = @_;

    my $timezone = $conf->{timezone};
    return if !$timezone;

    # Use systemd timezone handling
    my $path = "/etc/localtime";
    my $target = "/usr/share/zoneinfo/$timezone";

    # Check if timezone file exists
    if (! -f $self->{rootdir} . $target) {
        warn "timezone file $target not found, skipping timezone setup\n";
        return;
    }

    $self->ct_unlink($path);
    $self->ct_symlink($target, $path);
}

sub set_hostname {
    my ($self, $conf) = @_;

    my $hostname = $conf->{hostname} || 'localhost';
    my $namepart = ($hostname =~ s/\..*$//r);

    # Set hostname via /etc/hostname (systemd standard)
    $self->ct_file_set_contents("/etc/hostname", "$namepart\n");

    # Also update /etc/hosts
    my ($ipv4, $ipv6) = PVE::LXC::get_primary_ips($conf);
    my $hostip = $ipv4 || $ipv6;

    my $oldname = $self->ct_file_read_firstline("/etc/hostname") || 'localhost';
    my ($searchdomains) = $self->lookup_dns_conf($conf);

    $self->update_etc_hosts($hostip, $oldname, $hostname, $searchdomains);
}

sub set_dns {
    my ($self, $conf) = @_;

    # Skip for OCI containers - they use host-managed networking
    return if $self->{is_oci};

    my $searchdomains = $conf->{searchdomain} || "";
    my $nameservers = $conf->{nameserver} || "";

    return if !$searchdomains && !$nameservers;

    # Use systemd-resolved configuration
    my $content = "[Resolve]\n";

    if ($nameservers) {
        my @servers = split(/\s+/, $nameservers);
        foreach my $ns (@servers) {
            $content .= "DNS=$ns\n";
        }
    }

    if ($searchdomains) {
        my @domains = split(/\s+/, $searchdomains);
        foreach my $dom (@domains) {
            $content .= "Domains=$dom\n";
        }
    }

    $self->ct_mkdir("/etc/systemd/resolved.conf.d", 0755);
    $self->ct_file_set_contents("/etc/systemd/resolved.conf.d/pve.conf", $content);
}

sub setup_sshd {
    my ($self) = @_;

    # Skip for OCI containers - they don't run system services
    return if $self->{is_oci};

    # Enable SSH server if it exists
    my $sshd_service = "/usr/lib/systemd/system/sshd.service";
    my $ssh_service = "/usr/lib/systemd/system/ssh.service";

    if (-f $self->{rootdir} . $sshd_service) {
        $self->ct_symlink($sshd_service,
                          "/etc/systemd/system/multi-user.target.wants/sshd.service");
    } elsif (-f $self->{rootdir} . $ssh_service) {
        $self->ct_symlink($ssh_service,
                          "/etc/systemd/system/multi-user.target.wants/ssh.service");
    }
}

sub setup_securetty {
    my ($self) = @_;

    # Skip for OCI containers
    return if $self->{is_oci};

    # Configure securetty to allow console login via pct console
    my $securetty_file = "/etc/securetty";

    # Check if securetty exists
    if (-f $self->{rootdir} . $securetty_file) {
        my $content = $self->ct_file_read($securetty_file) // '';

        # Add pts/1 if not already present
        if ($content !~ m/^pts\/1$/m) {
            $content .= "pts/1\n";
            $self->ct_file_set_contents($securetty_file, $content);
        }
    } else {
        # Create securetty with pts/1 if it doesn't exist
        $self->ct_file_set_contents($securetty_file, "pts/1\n");
    }
}

sub post_create_hook {
    my ($self, $conf, $root_password, $ssh_keys) = @_;

    # Skip systemd-based setup for OCI containers
    # OCI containers use their entrypoint and host-managed networking
    if ($self->{is_oci}) {
        # Only call parent for basic setup (passwords, SSH keys if applicable)
        $self->SUPER::post_create_hook($conf, $root_password, $ssh_keys);
        return;
    }

    # Traditional LXC template setup with systemd
    $self->setup_network($conf);
    $self->setup_securetty();
    $self->setup_sshd();

    # Call parent implementation for standard setup
    $self->SUPER::post_create_hook($conf, $root_password, $ssh_keys);
}

sub unified_cgroupv2_support {
    # Chainguard with systemd fully supports cgroupv2
    return 1;
}

1;
