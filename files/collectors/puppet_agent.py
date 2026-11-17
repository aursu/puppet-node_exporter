#!/usr/bin/env python3
"""Puppet agent health as Prometheus metrics, for the node_exporter textfile collector.

Reads what the agent leaves behind after a run - the run summary, the run report and the lock
files in its state directory - and prints metrics in the Prometheus text format on stdout. It runs
on the host it describes, so it keeps reporting when the agent cannot reach its server, which is
exactly when a report processor on the server goes silent.

The run report carries Ruby object tags (!ruby/object:...), which the safe YAML loader rejects;
RubyTagLoader reads them as plain mappings. Nothing in the files is executed.

The error messages of the last run (log level err and above) are exported in full as labels of
puppet_last_run_error_info, so an alert can show what failed without logging in to the host. They
are what `puppet agent --test` prints; Puppet itself redacts Sensitive values in them.

Usage: puppet_agent.py [--summary FILE] [--report FILE] [--state-dir DIR] [--max-errors N]
"""
from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

import yaml

DEFAULT_SUMMARY = "/opt/puppetlabs/puppet/public/last_run_summary.yaml"
DEFAULT_REPORT = "/opt/puppetlabs/puppet/cache/state/last_run_report.yaml"
DEFAULT_STATE_DIR = "/opt/puppetlabs/puppet/cache/state"
DEFAULT_MAX_ERRORS = 10

# The C loader is much faster on large reports; fall back to the pure-Python one.
_BaseLoader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)


class RubyTagLoader(_BaseLoader):  # type: ignore[misc, valid-type]
    """A safe loader that reads !ruby/... tagged nodes as plain YAML values."""


def _construct_ruby_node(loader: yaml.SafeLoader, _suffix: str, node: yaml.Node) -> object:
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    return loader.construct_scalar(node)


RubyTagLoader.add_multi_constructor("!ruby/", _construct_ruby_node)


def _number(value: object) -> Optional[float]:
    """A YAML value as a float, or None when it is missing or not a number."""
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return None


def _mapping(value: object) -> dict:
    return value if isinstance(value, dict) else {}


@dataclass(frozen=True)
class Sample:
    """One line of a metric: its labels and value."""

    value: float
    labels: tuple[tuple[str, str], ...] = ()


@dataclass
class Metric:
    """A metric family: name, help text, type and its samples."""

    name: str
    help: str
    type: str = "gauge"
    samples: list[Sample] = field(default_factory=list)

    def add(self, value: float, **labels: str) -> "Metric":
        self.samples.append(Sample(value, tuple(sorted(labels.items()))))
        return self


class Exposition:
    """Writes metric families in the Prometheus text exposition format."""

    @staticmethod
    def _escape(value: str) -> str:
        return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')

    @staticmethod
    def _format_value(value: float) -> str:
        return str(int(value)) if value == int(value) else repr(value)

    def render(self, metrics: list[Metric]) -> str:
        lines: list[str] = []
        for metric in metrics:
            if not metric.samples:
                continue
            lines.append(f"# HELP {metric.name} {metric.help}")
            lines.append(f"# TYPE {metric.name} {metric.type}")
            for sample in metric.samples:
                labels = ",".join(f'{k}="{self._escape(v)}"' for k, v in sample.labels)
                selector = f"{{{labels}}}" if labels else ""
                lines.append(f"{metric.name}{selector} {self._format_value(sample.value)}")
        return "\n".join(lines) + "\n"


@dataclass(frozen=True)
class RunSummary:
    """last_run_summary.yaml: when the agent last ran, how long, what it changed or failed."""

    last_run: Optional[float]
    duration: Optional[float]
    resources: dict[str, float]
    events: dict[str, float]
    config_version: str
    puppet_version: str
    environment: str

    @classmethod
    def from_file(cls, path: Path) -> Optional["RunSummary"]:
        try:
            data = _mapping(yaml.load(path.read_text(encoding="utf-8"), Loader=RubyTagLoader))
        except (OSError, yaml.YAMLError):
            return None
        version = _mapping(data.get("version"))
        application = _mapping(data.get("application"))
        timing = _mapping(data.get("time"))
        return cls(
            last_run=_number(timing.get("last_run")),
            duration=_number(timing.get("total")),
            resources={k: v for k, v in ((k, _number(v)) for k, v in _mapping(data.get("resources")).items()) if v is not None},
            events={k: v for k, v in ((k, _number(v)) for k, v in _mapping(data.get("events")).items()) if v is not None},
            config_version=str(version.get("config", "") or ""),
            puppet_version=str(version.get("puppet", "") or ""),
            environment=str(application.get("converged_environment") or application.get("initial_environment") or ""),
        )


@dataclass(frozen=True)
class RunError:
    """One error message of a run: where it came from (a resource path or "Puppet") and its text."""

    level: str
    source: str
    message: str

    # Puppet's log levels from err up (Puppet::Util::Log.levels).
    LEVELS = ("err", "alert", "emerg", "crit")

    @classmethod
    def from_log(cls, log: object) -> Optional["RunError"]:
        """The error of one report log entry, or None for a notice, warning and the like."""
        entry = _mapping(log)
        level = str(entry.get("level", "") or "").lstrip(":")
        if level not in cls.LEVELS:
            return None
        return cls(level=level, source=str(entry.get("source", "") or ""),
                   message=str(entry.get("message", "") or "").strip())


@dataclass(frozen=True)
class RunReport:
    """last_run_report.yaml: the outcome of the last run, whether a cached catalog was used, and
    the run's error messages in the order they were logged, duplicates removed."""

    status: str
    cached_catalog_status: str
    errors: tuple[RunError, ...] = ()

    @classmethod
    def from_file(cls, path: Path) -> Optional["RunReport"]:
        try:
            data = _mapping(yaml.load(path.read_text(encoding="utf-8"), Loader=RubyTagLoader))
        except (OSError, yaml.YAMLError):
            return None
        logs = data.get("logs")
        errors = (RunError.from_log(log) for log in (logs if isinstance(logs, list) else []))
        return cls(
            status=str(data.get("status", "") or ""),
            cached_catalog_status=str(data.get("cached_catalog_status", "") or ""),
            errors=tuple(dict.fromkeys(e for e in errors if e is not None)),
        )


@dataclass(frozen=True)
class AgentState:
    """The agent's lock files: disabled by an operator, or a run in progress."""

    disabled: bool
    running: bool

    @classmethod
    def from_dir(cls, state_dir: Path) -> "AgentState":
        return cls(
            disabled=cls._exists(state_dir / "agent_disabled.lock"),
            running=cls._exists(state_dir / "agent_catalog_run.lock"),
        )

    @staticmethod
    def _exists(path: Path) -> bool:
        """Whether a lock file exists; an unreadable state directory counts as no lock."""
        try:
            return path.exists()
        except OSError:
            return False


class PuppetAgentCollector:
    """Turns the agent's files into metric families."""

    RESOURCE_STATES = ("total", "changed", "failed", "failed_to_restart", "out_of_sync", "corrective_change", "skipped")

    def __init__(self, summary: Path, report: Path, state_dir: Path, clock: Callable[[], float] = time.time,
                 max_errors: int = DEFAULT_MAX_ERRORS) -> None:
        self.summary_path = summary
        self.report_path = report
        self.state_dir = state_dir
        self.clock = clock
        self.max_errors = max_errors

    def collect(self) -> list[Metric]:
        summary = RunSummary.from_file(self.summary_path)
        report = RunReport.from_file(self.report_path)
        state = AgentState.from_dir(self.state_dir)

        metrics = [
            Metric("puppet_textfile_collector_success", "Whether the run summary could be read (1) or not (0).")
            .add(1.0 if summary else 0.0),
            Metric("puppet_textfile_collector_timestamp_seconds", "When this collector last ran, Unix time.")
            .add(self.clock()),
            Metric("puppet_agent_disabled", "Whether the agent is disabled (puppet agent --disable).")
            .add(1.0 if state.disabled else 0.0),
            Metric("puppet_agent_running", "Whether an agent run is in progress.")
            .add(1.0 if state.running else 0.0),
        ]
        if summary is None:
            return metrics

        if summary.last_run is not None:
            metrics.append(Metric("puppet_last_run_timestamp_seconds", "When the last agent run ended, Unix time.")
                           .add(summary.last_run))
        if summary.duration is not None:
            metrics.append(Metric("puppet_last_run_duration_seconds", "Duration of the last agent run.")
                           .add(summary.duration))

        resources = Metric("puppet_last_run_resources", "Resources of the last run, by state.")
        for state_name in self.RESOURCE_STATES:
            if state_name in summary.resources:
                resources.add(summary.resources[state_name], state=state_name)
        metrics.append(resources)

        events = Metric("puppet_last_run_events", "Events of the last run, by state.")
        for state_name in ("success", "failure"):
            if state_name in summary.events:
                events.add(summary.events[state_name], state=state_name)
        metrics.append(events)

        metrics.append(Metric("puppet_last_run_failed", "Whether the last run failed: report status failed, or failed resources or events.")
                       .add(1.0 if self._failed(summary, report) else 0.0))
        if report is not None:
            metrics.append(Metric("puppet_catalog_from_cache", "Whether the last run applied a cached catalog because compiling a new one failed.")
                           .add(1.0 if report.cached_catalog_status == "on_failure" else 0.0))
            metrics.append(Metric("puppet_last_run_errors", "Error messages (level err and above) of the last run.")
                           .add(float(len(report.errors))))
            error_info = Metric("puppet_last_run_error_info", "The first error messages of the last run, in full; always 1.")
            for index, error in enumerate(report.errors[:self.max_errors], start=1):
                error_info.add(1.0, index=str(index), level=error.level, source=error.source, message=error.message)
            metrics.append(error_info)

        metrics.append(Metric("puppet_agent_info", "The agent version, environment and catalog version of the last run.")
                       .add(1.0, version=summary.puppet_version, environment=summary.environment,
                            config_version=summary.config_version))
        return metrics

    @staticmethod
    def _failed(summary: RunSummary, report: Optional[RunReport]) -> bool:
        if report is not None and report.status == "failed":
            return True
        return summary.resources.get("failed", 0) > 0 or summary.events.get("failure", 0) > 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--summary", type=Path, default=Path(DEFAULT_SUMMARY))
    parser.add_argument("--report", type=Path, default=Path(DEFAULT_REPORT))
    parser.add_argument("--state-dir", type=Path, default=Path(DEFAULT_STATE_DIR))
    parser.add_argument("--max-errors", type=int, default=DEFAULT_MAX_ERRORS,
                        help="how many error messages of the last run to export (default %(default)s)")
    args = parser.parse_args(argv)
    collector = PuppetAgentCollector(args.summary, args.report, args.state_dir, max_errors=args.max_errors)
    sys.stdout.write(Exposition().render(collector.collect()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
