# @summary The node_exporter systemd service
#
# Private. The unit runs node_exporter as an unprivileged user with the filesystem read-only
# (ProtectSystem=strict): it only reads /proc, /sys and the textfile directory.
#
# @api private
class node_exporter::service {
  assert_private()

  if $node_exporter::manage_service {
    $port = $node_exporter::port

    $listen_args = $node_exporter::listen_address ? {
      undef   => ["--web.listen-address=:${port}"],
      default => $node_exporter::listen_address.map |$ip| {
        if ':' in $ip { "--web.listen-address=[${ip}]:${port}" } else { "--web.listen-address=${ip}:${port}" }
      },
    }

    $collector_args = $node_exporter::collectors_enable.map |$c| { "--collector.${c}" }
    + $node_exporter::collectors_disable.map |$c| { "--no-collector.${c}" }
    + $node_exporter::collector_flags.map |$k, $v| { "'--collector.${k}=${v}'" }

    $web_args = $node_exporter::web_config ? {
      undef   => [],
      default => ["--web.config.file=${node_exporter::web_config_file}"],
    }

    $args = $listen_args
    + ["--collector.textfile.directory=${node_exporter::textfile_dir}"]
    + $collector_args
    + $web_args

    systemd::manage_unit { 'node_exporter.service':
      unit_entry    => {
        'Description'   => 'Prometheus node_exporter',
        'Documentation' => 'https://github.com/prometheus/node_exporter',
        'Wants'         => 'network-online.target',
        'After'         => 'network-online.target',
      },
      service_entry => {
        'Type'                 => 'simple',
        'User'                 => $node_exporter::user,
        'Group'                => $node_exporter::group,
        'ExecStart'            => join(['/usr/local/bin/node_exporter'] + $args, ' '),
        'Restart'              => 'on-failure',
        'RestartSec'           => '5',
        'NoNewPrivileges'      => true,
        'ProtectSystem'        => 'strict',
        'ProtectHome'          => 'read-only',
        'PrivateTmp'           => true,
        'ProtectControlGroups' => true,
        'ProtectKernelModules' => true,
        'RestrictSUIDSGID'     => true,
        'LockPersonality'      => true,
      },
      install_entry => {
        'WantedBy' => 'multi-user.target',
      },
      enable        => true,
      active        => true,
    }
  }
}
