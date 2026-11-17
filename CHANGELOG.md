# Changelog

All notable changes to this project will be documented in this file.

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
