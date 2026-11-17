# Changelog

All notable changes to this project will be documented in this file.

## Release 0.2.0

**Features**

- `node_exporter::collector::puppet`: the error messages of the last run (log level err and
  above) in full - `puppet_last_run_errors` counts them, `puppet_last_run_error_info{index,level,
  source,message}` carries the first `max_errors` (new parameter, default 10), so an alert can show
  what failed.

**Bugfixes**

- README: the example `PuppetRunFailing` expression fired twice per host - and failed as a rule -
  when both signals were 1 (`a == 1 or b == 1` keeps the metric names); now
  `max without (__name__) (...)`.

**Tests**

- A real `last_run_summary.yaml` written by openvox-agent 8.28.1 as a fixture of the collector
  tests; a failed run report with catalog, resource and multi-line errors.

## Release 0.1.0

**Features**

- `node_exporter`: installs node_exporter 1.12.1 from the GitHub release (or a mirror), verified
  against a pinned sha256 digest - an unknown digest fails the catalog; hardened systemd service;
  listen addresses (IPv4/IPv6), collectors and collector flags; optional web configuration (TLS,
  basic auth); textfile directory.
- `node_exporter::textfile`: a command run by a systemd timer, its stdout published atomically as
  `<name>.prom` in the textfile directory, in a sandbox.
- `node_exporter::collector::puppet`: Puppet agent health (last run time and duration, resources,
  events, failure, cached catalog, disabled / running) by a Python collector on a textfile timer.
