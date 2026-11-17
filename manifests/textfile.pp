# @summary A textfile collector: a command run by a systemd timer, its output published as metrics
#
# The command prints metrics in the Prometheus text format on stdout. A oneshot service runs it on
# a timer, writes the output to a hidden temporary file in the textfile directory and renames it to
# "<name>.prom" only when the command succeeded - so node_exporter never reads a half-written file,
# and a failing command leaves the previous file in place (its age shows in
# node_textfile_mtime_seconds).
#
# Usable without the node_exporter class, e.g. on a host where node_exporter runs in a container
# that mounts the textfile directory. The directory must exist (the node_exporter class creates it).
#
# The service runs as root by default (collectors often read root-only files) inside a sandbox: the
# filesystem is read-only except the textfile directory and $read_write_paths.
#
# @param command
#   The command as an argument vector; each element is quoted for the shell. Default: the installed
#   $script_content.
# @param script_content
#   A collector script to install as /usr/local/lib/node_exporter/collectors/<name> (0755).
# @param on_calendar
#   When to run, as systemd OnCalendar.
# @param textfile_directory
#   The textfile directory. Default: the node_exporter class's, else /var/lib/node_exporter/textfile.
# @param user
#   User the command runs as.
# @param read_write_paths
#   Further paths the command may write to.
# @param ensure
#   'absent' removes the units, the script and the metrics file.
#
# @example
#   node_exporter::textfile { 'apt':
#     command     => ['/usr/local/bin/apt_info.py'],
#     on_calendar => 'hourly',
#   }
define node_exporter::textfile (
  Optional[Array[String[1], 1]]  $command            = undef,
  Optional[String[1]]            $script_content     = undef,
  String[1]                      $on_calendar        = '*:0/5',
  Optional[Stdlib::Absolutepath] $textfile_directory = undef,
  String[1]                      $user               = 'root',
  Array[Stdlib::Absolutepath]    $read_write_paths   = [],
  Enum['present', 'absent']      $ensure             = 'present',
) {
  unless $name =~ /\A[a-z0-9_]+\z/ {
    fail("node_exporter::textfile: name '${name}' must be lower-case letters, digits and '_' (it names a metrics file)")
  }

  $dir         = pick($textfile_directory, getvar('node_exporter::textfile_dir'), '/var/lib/node_exporter/textfile')
  $output      = "${dir}/${name}.prom"
  $tmp         = "${dir}/.${name}.prom.tmp"
  $script_path = "/usr/local/lib/node_exporter/collectors/${name}"
  $unit        = "node_exporter-textfile-${name}"

  if $script_content {
    ensure_resource('file', ['/usr/local/lib/node_exporter', '/usr/local/lib/node_exporter/collectors'], {
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
    })

    file { $script_path:
      ensure  => stdlib::ensure($ensure, 'file'),
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      content => $script_content,
    }
  }

  $argv = $command ? {
    undef   => [$script_path],
    default => $command,
  }

  if $ensure == 'present' and !$command and !$script_content {
    fail("node_exporter::textfile[${name}]: set command or script_content")
  }

  $exec = join($argv.map |$a| { shell_escape($a) }, ' ')

  systemd::manage_unit { "${unit}.service":
    ensure        => $ensure,
    unit_entry    => {
      'Description' => "node_exporter textfile collector ${name}",
    },
    service_entry => {
      'Type'                 => 'oneshot',
      'User'                 => $user,
      'ExecStart'            => "/bin/sh -c '${exec} > ${tmp}'",
      'ExecStartPost'        => "/bin/mv -f ${tmp} ${output}",
      'NoNewPrivileges'      => true,
      'ProtectSystem'        => 'strict',
      'ProtectHome'          => 'read-only',
      'PrivateTmp'           => true,
      'ReadWritePaths'       => [$dir] + $read_write_paths,
      'ProtectControlGroups' => true,
      'ProtectKernelModules' => true,
      'RestrictSUIDSGID'     => true,
      'LockPersonality'      => true,
    },
  }

  systemd::manage_unit { "${unit}.timer":
    ensure        => $ensure,
    unit_entry    => {
      'Description' => "Run the node_exporter textfile collector ${name}",
    },
    timer_entry   => {
      'OnCalendar'         => $on_calendar,
      'RandomizedDelaySec' => '30',
      'Persistent'         => true,
    },
    install_entry => {
      'WantedBy' => 'timers.target',
    },
    enable        => $ensure == 'present',
    active        => $ensure == 'present',
  }

  if $ensure == 'absent' {
    file { [$output, $tmp]:
      ensure => absent,
    }
  }
}
