# @summary Install and run Prometheus node_exporter
#
# Installs node_exporter from the upstream GitHub release (a single static binary), verified
# against a pinned digest, and runs it as a hardened systemd service. A textfile collector
# directory is always created, so that collector scripts (see `node_exporter::textfile`) can
# publish their own metrics next to the built-in ones.
#
# The download is verified: `puppet/archive` checks a digest only when one is given, and accepts
# whatever the endpoint returns otherwise. A version with no known digest is a hard failure rather
# than an unverified install.
#
# Do not use this class on a host that already runs node_exporter on the same port, such as a
# Kubernetes node with the node-exporter DaemonSet of kube-prometheus-stack.
#
# @param version
#   node_exporter version to install.
# @param checksum
#   Digest of the release asset. Overrides the lookup in $checksums.
# @param checksums
#   Known-good digests keyed by release asset filename, e.g.
#   'node_exporter-1.12.1.linux-amd64.tar.gz'. Shipped in the module data for the default version.
# @param checksum_type
#   Digest algorithm for $checksum / $checksums.
# @param source_url
#   Base URL the release assets are downloaded from: an internal mirror, for example. Default: the
#   GitHub release of $version. The digest is checked whatever the source.
# @param listen_address
#   Addresses to listen on, one `--web.listen-address` each. Default: all interfaces.
# @param port
#   Port to listen on.
# @param state_dir
#   Home and state directory of the service user.
# @param textfile_directory
#   Directory of the textfile collector. Default: "${state_dir}/textfile".
# @param collectors_enable
#   Collectors to enable in addition to the defaults, e.g. ['systemd'].
# @param collectors_disable
#   Default collectors to disable.
# @param collector_flags
#   Further collector flags without the leading '--collector.', e.g.
#   { 'systemd.unit-include' => '(ssh|cron)\.service' }.
# @param web_config
#   Content of the web configuration file (TLS, basic authentication), as documented by the
#   Prometheus exporter-toolkit. Written to /etc/node_exporter/web-config.yml when given.
# @param user
#   Service user.
# @param group
#   Service group.
# @param manage_user
#   Whether to create the service user and group.
# @param manage_service
#   Whether to manage the systemd unit and keep the service running.
#
# @example
#   class { 'node_exporter':
#     listen_address    => ['10.0.0.5'],
#     collectors_enable => ['systemd'],
#   }
class node_exporter (
  String[1]                                         $version            = '1.12.1',
  Optional[String[1]]                               $checksum           = undef,
  Hash[String[1], String[1]]                        $checksums          = {},
  Enum['sha256', 'sha512']                          $checksum_type      = 'sha256',
  Optional[Stdlib::HTTPUrl]                         $source_url         = undef,
  Optional[Array[Stdlib::IP::Address::Nosubnet, 1]] $listen_address     = undef,
  Stdlib::Port                                      $port               = 9100,
  Stdlib::Absolutepath                              $state_dir          = '/var/lib/node_exporter',
  Optional[Stdlib::Absolutepath]                    $textfile_directory = undef,
  Array[String[1]]                                  $collectors_enable  = [],
  Array[String[1]]                                  $collectors_disable = [],
  Hash[String[1], String[1]]                        $collector_flags    = {},
  Optional[Hash[String[1], Data]]                   $web_config         = undef,
  String[1]                                         $user               = 'node-exporter',
  String[1]                                         $group              = 'node-exporter',
  Boolean                                           $manage_user        = true,
  Boolean                                           $manage_service     = true,
) {
  $textfile_dir = pick($textfile_directory, "${state_dir}/textfile")
  $web_config_file = '/etc/node_exporter/web-config.yml'

  contain node_exporter::install
  contain node_exporter::config
  contain node_exporter::service

  Class['node_exporter::install']
  -> Class['node_exporter::config']
  ~> Class['node_exporter::service']

  Class['node_exporter::install'] ~> Class['node_exporter::service']
}
