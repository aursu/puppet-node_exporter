# @summary Download, verify and install the node_exporter binary
#
# Private. The release tarball is downloaded, checked against its digest and extracted to
# /opt/node_exporter-<version>.linux-<arch>; /usr/local/bin/node_exporter points at the binary in
# it. A new version gets a new directory, so an upgrade or a rollback is a change of the link.
#
# @api private
class node_exporter::install {
  assert_private()

  $version = $node_exporter::version

  $arch = $facts['os']['architecture'] ? {
    'aarch64' => 'arm64',
    'arm64'   => 'arm64',
    default   => 'amd64',
  }
  $dirname = "node_exporter-${version}.linux-${arch}"
  $asset   = "${dirname}.tar.gz"
  $binary  = "/opt/${dirname}/node_exporter"
  $base    = pick($node_exporter::source_url, "https://github.com/prometheus/node_exporter/releases/download/v${version}")

  # An explicit checksum wins; otherwise the digest must be known for this exact asset. No digest
  # means no install - see the class documentation.
  if $node_exporter::checksum {
    $asset_checksum = $node_exporter::checksum
  }
  else {
    $asset_checksum = $node_exporter::checksums[$asset]
  }

  unless $asset_checksum {
    $err_what = "node_exporter: no ${node_exporter::checksum_type} digest known for ${asset}."
    $err_fix  = 'Add it to node_exporter::checksums, or set node_exporter::checksum.'
    fail("${err_what} ${err_fix} Refusing to install an unverified binary.")
  }

  if $node_exporter::manage_user {
    $nologin = $facts['os']['family'] ? {
      'Debian' => '/usr/sbin/nologin',
      default  => '/sbin/nologin',
    }

    group { $node_exporter::group:
      ensure => present,
      system => true,
    }

    user { $node_exporter::user:
      ensure     => present,
      system     => true,
      gid        => $node_exporter::group,
      home       => $node_exporter::state_dir,
      managehome => false,
      shell      => $nologin,
      comment    => 'Prometheus node_exporter',
      require    => Group[$node_exporter::group],
    }
  }

  archive { "/tmp/${asset}":
    ensure          => present,
    source          => "${base}/${asset}",
    extract         => true,
    extract_path    => '/opt',
    creates         => $binary,
    cleanup         => true,
    checksum        => $asset_checksum,
    checksum_type   => $node_exporter::checksum_type,
    checksum_verify => true,
    user            => 'root',
    group           => 'root',
  }

  file { '/usr/local/bin/node_exporter':
    ensure  => link,
    target  => $binary,
    require => Archive["/tmp/${asset}"],
  }
}
