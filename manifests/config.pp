# @summary State, textfile and web configuration of node_exporter
#
# Private. The textfile directory belongs to root: collector scripts run as root and write their
# files there, node_exporter only reads them.
#
# @api private
class node_exporter::config {
  assert_private()

  file { $node_exporter::state_dir:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { $node_exporter::textfile_dir:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  if $node_exporter::web_config {
    file { '/etc/node_exporter':
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755',
    }

    # 0640, group of the service: may hold the TLS key path and basic auth hashes.
    file { $node_exporter::web_config_file:
      ensure  => file,
      owner   => 'root',
      group   => $node_exporter::group,
      mode    => '0640',
      content => stdlib::to_yaml($node_exporter::web_config),
    }
  }
  else {
    file { $node_exporter::web_config_file:
      ensure => absent,
    }
  }
}
