"""Unit tests of files/collectors/puppet_agent.py. Run: python3 -m unittest discover -s spec/python"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[2] / "files" / "collectors" / "puppet_agent.py"
# A real run summary, as openvox-agent 8.28.1 wrote it (a run that changed 17 of 323 resources).
_FIXTURES = Path(__file__).resolve().parent / "fixtures"
_spec = importlib.util.spec_from_file_location("puppet_agent", _SCRIPT)
puppet_agent = importlib.util.module_from_spec(_spec)
sys.modules["puppet_agent"] = puppet_agent  # dataclasses look their module up there
_spec.loader.exec_module(puppet_agent)  # type: ignore[union-attr]

SUMMARY = """---
version:
  config: 1763341200
  puppet: 8.28.1
application:
  run_mode: agent
  initial_environment: production
  converged_environment: production
resources:
  changed: 2
  corrective_change: 0
  failed: 0
  failed_to_restart: 0
  out_of_sync: 2
  restarted: 0
  scheduled: 0
  skipped: 0
  total: 612
time:
  catalog_application: 9.81
  config_retrieval: 3.12
  total: 14.53
  last_run: 1763341391
changes:
  total: 2
events:
  failure: 0
  success: 2
  total: 2
"""

REPORT = """--- !ruby/object:Puppet::Transaction::Report
host: web1.example.org
time: 2026-11-17 01:03:11.000000000 +00:00
configuration_version: 1763341200
report_format: 12
puppet_version: 8.28.1
status: {status}
transaction_completed: true
noop: false
environment: production
cached_catalog_status: {cached}
logs:
- !ruby/object:Puppet::Util::Log
  level: !ruby/sym notice
  message: Applied catalog in 9.81 seconds
resource_statuses: {{}}
"""

# A failed run: a catalog compile error, two failed resources, one of them logged twice, a
# warning and a multi-line message. Levels as Puppet writes them (Ruby symbols).
FAILED_REPORT = """--- !ruby/object:Puppet::Transaction::Report
host: web1.example.org
status: failed
cached_catalog_status: not_used
logs:
- !ruby/object:Puppet::Util::Log
  level: !ruby/sym warning
  message: Unable to fetch my node definition, but the agent run will continue
  source: Puppet
- !ruby/object:Puppet::Util::Log
  level: !ruby/sym err
  message: 'Could not retrieve catalog from remote server: Error 500 on SERVER: Server Error: Evaluation Error: Unknown variable: ''$foo'' (file: /etc/puppetlabs/code/environments/production/site/profile/manifests/base.pp, line: 42, column: 7) on node web1.example.org'
  source: Puppet
- !ruby/object:Puppet::Util::Log
  level: !ruby/sym err
  message: |-
    change from 'absent' to 'present' failed: Execution of '/usr/bin/apt-get -q -y install nginx' returned 100: E: Unable to locate package nginx
  source: /Stage[main]/Profile::Web/Package[nginx]/ensure
- !ruby/object:Puppet::Util::Log
  level: !ruby/sym err
  message: |-
    change from 'absent' to 'present' failed: Execution of '/usr/bin/apt-get -q -y install nginx' returned 100: E: Unable to locate package nginx
  source: /Stage[main]/Profile::Web/Package[nginx]/ensure
- !ruby/object:Puppet::Util::Log
  level: !ruby/sym crit
  message: "Could not start Service[nginx]: Execution of 'systemctl start nginx' returned 1:\\nJob for nginx.service failed."
  source: /Stage[main]/Profile::Web/Service[nginx]/ensure
- !ruby/object:Puppet::Util::Log
  level: !ruby/sym notice
  message: Applied catalog in 3.20 seconds
  source: Puppet
resource_statuses: {}
"""


class CollectorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.summary = self.dir / "last_run_summary.yaml"
        self.report = self.dir / "last_run_report.yaml"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def render(self) -> str:
        collector = puppet_agent.PuppetAgentCollector(self.summary, self.report, self.dir, clock=lambda: 1763341500.0)
        return puppet_agent.Exposition().render(collector.collect())

    def write(self, status: str = "changed", cached: str = "not_used", summary: str = SUMMARY) -> None:
        self.summary.write_text(summary, encoding="utf-8")
        self.report.write_text(REPORT.format(status=status, cached=cached), encoding="utf-8")

    def test_healthy_run(self) -> None:
        self.write()
        out = self.render()
        self.assertIn("puppet_textfile_collector_success 1\n", out)
        self.assertIn("puppet_textfile_collector_timestamp_seconds 1763341500\n", out)
        self.assertIn("puppet_last_run_timestamp_seconds 1763341391\n", out)
        self.assertIn("puppet_last_run_duration_seconds 14.53\n", out)
        self.assertIn('puppet_last_run_resources{state="total"} 612\n', out)
        self.assertIn('puppet_last_run_resources{state="changed"} 2\n', out)
        self.assertIn('puppet_last_run_events{state="failure"} 0\n', out)
        self.assertIn("puppet_last_run_failed 0\n", out)
        self.assertIn("puppet_catalog_from_cache 0\n", out)
        self.assertIn('puppet_agent_info{config_version="1763341200",environment="production",version="8.28.1"} 1\n', out)
        self.assertIn("puppet_agent_disabled 0\n", out)
        self.assertIn("# TYPE puppet_last_run_failed gauge\n", out)

    def test_failed_report(self) -> None:
        self.write(status="failed")
        self.assertIn("puppet_last_run_failed 1\n", self.render())

    def test_failed_resources_without_report(self) -> None:
        self.summary.write_text(SUMMARY.replace("  failed: 0\n", "  failed: 3\n"), encoding="utf-8")
        out = self.render()
        self.assertIn("puppet_last_run_failed 1\n", out)
        self.assertNotIn("puppet_catalog_from_cache", out)

    def test_cached_catalog_after_compile_failure(self) -> None:
        self.write(cached="on_failure")
        self.assertIn("puppet_catalog_from_cache 1\n", self.render())

    def test_missing_summary(self) -> None:
        out = self.render()
        self.assertIn("puppet_textfile_collector_success 0\n", out)
        self.assertNotIn("puppet_last_run_timestamp_seconds", out)

    def test_unreadable_summary(self) -> None:
        self.summary.write_text("version: [unclosed\n", encoding="utf-8")
        self.assertIn("puppet_textfile_collector_success 0\n", self.render())

    def test_catalog_failure_summary(self) -> None:
        # A run that never got a catalog writes a summary without resources.
        self.summary.write_text("---\nversion:\n  config:\n  puppet: 8.28.1\ntime:\n  last_run: 1763341391\n", encoding="utf-8")
        out = self.render()
        self.assertIn("puppet_last_run_timestamp_seconds 1763341391\n", out)
        self.assertNotIn("puppet_last_run_resources", out)
        self.assertIn('config_version=""', out)

    def test_locks(self) -> None:
        self.write()
        (self.dir / "agent_disabled.lock").write_text('{"disabled_message":"maintenance"}', encoding="utf-8")
        (self.dir / "agent_catalog_run.lock").write_text("1234", encoding="utf-8")
        out = self.render()
        self.assertIn("puppet_agent_disabled 1\n", out)
        self.assertIn("puppet_agent_running 1\n", out)

    def test_label_escaping(self) -> None:
        self.assertEqual(puppet_agent.Exposition._escape('a"b\\c\nd'), 'a\\"b\\\\c\\nd')

    def test_real_openvox_summary(self) -> None:
        self.summary.write_text((_FIXTURES / "last_run_summary-openvox-8.28.1.yaml").read_text(encoding="utf-8"),
                                encoding="utf-8")
        out = self.render()
        self.assertIn("puppet_textfile_collector_success 1\n", out)
        self.assertIn("puppet_last_run_timestamp_seconds 1794878541\n", out)
        self.assertIn("puppet_last_run_duration_seconds 27.197605649\n", out)
        self.assertIn('puppet_last_run_resources{state="total"} 323\n', out)
        self.assertIn('puppet_last_run_resources{state="changed"} 17\n', out)
        self.assertIn('puppet_last_run_events{state="success"} 17\n', out)
        self.assertIn("puppet_last_run_failed 0\n", out)
        self.assertIn('puppet_agent_info{config_version="1794878521",environment="production",version="8.28.1"} 1\n', out)

    def test_healthy_run_has_no_errors(self) -> None:
        self.write()
        out = self.render()
        self.assertIn("puppet_last_run_errors 0\n", out)
        self.assertNotIn("puppet_last_run_error_info", out)

    def test_failed_run_errors_in_full(self) -> None:
        self.summary.write_text(SUMMARY, encoding="utf-8")
        self.report.write_text(FAILED_REPORT, encoding="utf-8")
        out = self.render()
        self.assertIn("puppet_last_run_failed 1\n", out)
        # err and crit count, the warning and the notice do not; the repeated message once.
        self.assertIn("puppet_last_run_errors 3\n", out)
        self.assertIn('puppet_last_run_error_info{index="1",level="err",message="Could not retrieve catalog from remote server: '
                      'Error 500 on SERVER: Server Error: Evaluation Error: Unknown variable: \'$foo\' (file: '
                      '/etc/puppetlabs/code/environments/production/site/profile/manifests/base.pp, line: 42, column: 7) '
                      'on node web1.example.org",source="Puppet"} 1\n', out)
        self.assertIn('{index="2",level="err",message="change from \'absent\' to \'present\' failed: Execution of '
                      '\'/usr/bin/apt-get -q -y install nginx\' returned 100: E: Unable to locate package nginx",'
                      'source="/Stage[main]/Profile::Web/Package[nginx]/ensure"} 1\n', out)
        # The full text, line breaks escaped as the exposition format requires.
        self.assertIn('{index="3",level="crit",message="Could not start Service[nginx]: Execution of \'systemctl start nginx\' '
                      'returned 1:\\nJob for nginx.service failed.",source="/Stage[main]/Profile::Web/Service[nginx]/ensure"} 1\n', out)

    def test_error_count_bounded(self) -> None:
        self.summary.write_text(SUMMARY, encoding="utf-8")
        self.report.write_text(FAILED_REPORT, encoding="utf-8")
        collector = puppet_agent.PuppetAgentCollector(self.summary, self.report, self.dir, clock=lambda: 0.0, max_errors=1)
        out = puppet_agent.Exposition().render(collector.collect())
        self.assertIn("puppet_last_run_errors 3\n", out)
        self.assertEqual(out.count("puppet_last_run_error_info{"), 1)


if __name__ == "__main__":
    unittest.main()
