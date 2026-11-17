# node_exporter

Installs [Prometheus node_exporter](https://github.com/prometheus/node_exporter) on Linux hosts
from the upstream release, **verified against a pinned digest**, runs it as a hardened systemd
service, and gives it a textfile collector with timers for your own collector scripts - including
one for the health of the Puppet agent itself.

## Why another node_exporter module

- **The download is verified.** `puppet/archive` checks a digest only when one is given. This
  module always gives one: digests of the release assets ship in the module data, and a version
  without a known digest fails the catalog instead of installing an unverified binary.
- **Small and single-purpose.** One exporter, no Prometheus server, no other exporters.
- **Textfile collectors as a first-class feature**, run by systemd timers, published atomically.

## Requirements

Puppet 7.24+ or OpenVox 8+, `puppetlabs/stdlib` 9+, `puppet/archive`, `puppet/systemd`. Tested on
Ubuntu 20.04/22.04/24.04 and Rocky Linux 8/9/10 (the binary is static; other systemd Linux
distributions should work).

## Usage

```puppet
include node_exporter
```

installs version 1.12.1 from GitHub, runs `node_exporter.service` as user `node-exporter` on port
9100 on all interfaces, with the textfile directory `/var/lib/node_exporter/textfile`.

```puppet
class { 'node_exporter':
  listen_address    => ['10.0.0.5'],                 # one --web.listen-address per address
  collectors_enable => ['systemd'],
  collector_flags   => { 'systemd.unit-include' => '(ssh|cron)\.service' },
  source_url        => 'https://mirror.example.org/node_exporter',   # the digest is checked anyway
  web_config        => {                             # TLS / basic auth, exporter-toolkit format
    'basic_auth_users' => { 'prometheus' => '$2y$10$...bcrypt hash...' },
  },
}
```

Do not use the class on a host where node_exporter already runs on the same port, such as a
Kubernetes node with the node-exporter DaemonSet of kube-prometheus-stack.

### Upgrading

Set `node_exporter::version` **and** add the digests of the new release assets to
`node_exporter::checksums` (or set `node_exporter::checksum`). Each version is extracted to its own
`/opt/node_exporter-<version>.linux-<arch>` directory; `/usr/local/bin/node_exporter` points at the
current one, so a rollback is a change of the version. Old directories are not removed.

How the shipped digests were established is described in `data/common.yaml`. node_exporter
releases are not signed: the digest protects against a corrupted or swapped download, not against a
compromised release.

### Textfile collectors

```puppet
node_exporter::textfile { 'apt':
  command     => ['/usr/local/bin/apt_info.py'],
  on_calendar => 'hourly',
}

node_exporter::textfile { 'backup_age':
  script_content => file('profile/backup_age.py'),   # installed under /usr/local/lib/node_exporter/collectors/
}
```

The command prints metrics in the Prometheus text format on stdout. A oneshot service, run by a
timer (`*:0/5` by default), writes the output to a temporary file and renames it to `<name>.prom`
only when the command succeeded: node_exporter never reads a half-written file, and a failing
command leaves the previous file, whose age shows in `node_textfile_mtime_seconds`. The service
runs as root by default in a sandbox (read-only filesystem except the textfile directory).

The define does not need the class: it works on hosts where node_exporter runs elsewhere (e.g. in a
container mounting the textfile directory), as long as the directory exists.

### Puppet agent health

```puppet
include node_exporter::collector::puppet
```

installs a Python 3 collector (with PyYAML from the OS packages) that reads the agent's run summary,
run report and lock files every five minutes. It runs on the host itself, so it keeps reporting
when the agent cannot reach its server.

| Metric | Meaning |
|---|---|
| `puppet_last_run_timestamp_seconds` | when the last run ended |
| `puppet_last_run_duration_seconds` | how long it took |
| `puppet_last_run_resources{state}` | total, changed, failed, failed_to_restart, out_of_sync, corrective_change, skipped |
| `puppet_last_run_events{state}` | success, failure |
| `puppet_last_run_failed` | 1 when the report says failed, or resources or events failed |
| `puppet_catalog_from_cache` | 1 when a cached catalog was applied because compiling failed |
| `puppet_agent_disabled`, `puppet_agent_running` | the agent's lock files |
| `puppet_agent_info{version,environment,config_version}` | always 1 |
| `puppet_textfile_collector_success`, `..._timestamp_seconds` | the collector itself |

Example alerts:

```yaml
- alert: PuppetAgentStale
  expr: time() - puppet_last_run_timestamp_seconds > 7200
- alert: PuppetRunFailing
  expr: puppet_last_run_failed == 1 or puppet_catalog_from_cache == 1
  for: 3h
```

## Reference

See the `@param` documentation in the manifests (`pdk bundle exec puppet strings`).

## Development

`pdk validate`, `pdk test unit`; the collector's tests: `python3 -m unittest discover -s spec/python`.
