# @summary Puppet agent health as metrics in the node_exporter textfile directory
#
# Installs the collector script (Python 3, PyYAML) and runs it every few minutes through
# `node_exporter::textfile`. It reads the agent's run summary, run report and lock files - on the
# host itself, so it keeps reporting when the agent cannot reach its server. Metrics:
# puppet_last_run_timestamp_seconds, puppet_last_run_duration_seconds, puppet_last_run_resources,
# puppet_last_run_events, puppet_last_run_failed, puppet_catalog_from_cache, puppet_agent_disabled,
# puppet_agent_running, puppet_agent_info, puppet_textfile_collector_success.
#
# @param summary_file
#   The agent's run summary (puppet config print lastrunfile).
# @param report_file
#   The agent's last run report (puppet config print lastrunreport).
# @param state_dir
#   The agent's state directory, holding the lock files (puppet config print statedir).
# @param on_calendar
#   When to collect, as systemd OnCalendar.
# @param manage_python
#   Whether to install Python 3 and PyYAML from the OS packages.
# @param python
#   The Python 3 interpreter.
#
# @example
#   include node_exporter
#   include node_exporter::collector::puppet
class node_exporter::collector::puppet (
  Stdlib::Absolutepath $summary_file  = '/opt/puppetlabs/puppet/public/last_run_summary.yaml',
  Stdlib::Absolutepath $report_file   = '/opt/puppetlabs/puppet/cache/state/last_run_report.yaml',
  Stdlib::Absolutepath $state_dir     = '/opt/puppetlabs/puppet/cache/state',
  String[1]            $on_calendar   = '*:0/5',
  Boolean              $manage_python = true,
  Stdlib::Absolutepath $python        = '/usr/bin/python3',
) {
  if $manage_python {
    $packages = $facts['os']['family'] ? {
      'Debian' => ['python3', 'python3-yaml'],
      default  => ['python3', 'python3-pyyaml'],
    }
    stdlib::ensure_packages($packages)
  }

  node_exporter::textfile { 'puppet_agent':
    script_content => file('node_exporter/collectors/puppet_agent.py'),
    command        => [
      $python, '/usr/local/lib/node_exporter/collectors/puppet_agent',
      '--summary', $summary_file,
      '--report', $report_file,
      '--state-dir', $state_dir,
    ],
    on_calendar    => $on_calendar,
  }
}
