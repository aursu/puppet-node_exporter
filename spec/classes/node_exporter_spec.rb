# frozen_string_literal: true

require 'spec_helper'

describe 'node_exporter' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:asset) { 'node_exporter-1.12.1.linux-amd64.tar.gz' }

      context 'with default parameters' do
        it { is_expected.to compile.with_all_deps }

        it {
          is_expected.to contain_group('node-exporter').with(ensure: 'present', system: true)
        }

        it {
          nologin = (os_facts[:os]['family'] == 'Debian') ? '/usr/sbin/nologin' : '/sbin/nologin'
          is_expected.to contain_user('node-exporter')
            .with(ensure: 'present', system: true, gid: 'node-exporter', home: '/var/lib/node_exporter', shell: nologin)
        }

        # The digest comes from the module's own data and is always verified.
        it {
          is_expected.to contain_archive("/tmp/#{asset}")
            .with(
              source: "https://github.com/prometheus/node_exporter/releases/download/v1.12.1/#{asset}",
              extract: true,
              extract_path: '/opt',
              creates: '/opt/node_exporter-1.12.1.linux-amd64/node_exporter',
              checksum: 'b51d8a76aa2a9156a55d501aca6276fae09e262259a5e4e831d2c2222f084e63',
              checksum_type: 'sha256',
              checksum_verify: true,
            )
        }

        it {
          is_expected.to contain_file('/usr/local/bin/node_exporter')
            .with(ensure: 'link', target: '/opt/node_exporter-1.12.1.linux-amd64/node_exporter')
            .that_requires("Archive[/tmp/#{asset}]")
        }

        it { is_expected.to contain_file('/var/lib/node_exporter').with(ensure: 'directory', owner: 'root', mode: '0755') }
        it { is_expected.to contain_file('/var/lib/node_exporter/textfile').with(ensure: 'directory', owner: 'root', mode: '0755') }
        it { is_expected.to contain_file('/etc/node_exporter/web-config.yml').with_ensure('absent') }

        it {
          is_expected.to contain_systemd__manage_unit('node_exporter.service')
            .with(enable: true, active: true)
            .with_service_entry(
              'Type' => 'simple',
              'User' => 'node-exporter',
              'Group' => 'node-exporter',
              'ExecStart' => '/usr/local/bin/node_exporter --web.listen-address=:9100 --collector.textfile.directory=/var/lib/node_exporter/textfile',
              'Restart' => 'on-failure',
              'RestartSec' => '5',
              'NoNewPrivileges' => true,
              'ProtectSystem' => 'strict',
              'ProtectHome' => 'read-only',
              'PrivateTmp' => true,
              'ProtectControlGroups' => true,
              'ProtectKernelModules' => true,
              'RestrictSUIDSGID' => true,
              'LockPersonality' => true,
            )
        }
      end

      context 'with listen addresses, collectors and flags' do
        let(:params) do
          {
            listen_address: ['10.0.0.5', 'fd00::5'],
            port: 9200,
            collectors_enable: ['systemd'],
            collectors_disable: ['wifi'],
            collector_flags: { 'systemd.unit-include' => '(ssh|cron)\.service' },
          }
        end

        it {
          exec_start = catalogue.resource('Systemd::Manage_unit', 'node_exporter.service')[:service_entry]['ExecStart']
          expect(exec_start).to eq(
            '/usr/local/bin/node_exporter --web.listen-address=10.0.0.5:9200 --web.listen-address=[fd00::5]:9200 ' \
            '--collector.textfile.directory=/var/lib/node_exporter/textfile --collector.systemd --no-collector.wifi ' \
            "'--collector.systemd.unit-include=(ssh|cron)\\.service'",
          )
        }
      end

      context 'with a web configuration' do
        let(:params) { { web_config: { 'basic_auth_users' => { 'prometheus' => '$2y$10$hash' } } } }

        it {
          is_expected.to contain_file('/etc/node_exporter/web-config.yml')
            .with(ensure: 'file', owner: 'root', group: 'node-exporter', mode: '0640')
            .with_content(%r{basic_auth_users:\n\s+prometheus: "\$2y\$10\$hash"})
        }

        it {
          exec_start = catalogue.resource('Systemd::Manage_unit', 'node_exporter.service')[:service_entry]['ExecStart']
          expect(exec_start).to match(%r{ --web.config.file=/etc/node_exporter/web-config.yml$})
        }
      end

      context 'with a custom textfile directory and state dir' do
        let(:params) { { state_dir: '/srv/ne', textfile_directory: '/srv/ne/prom' } }

        it { is_expected.to contain_file('/srv/ne/prom').with_ensure('directory') }
        it { is_expected.to contain_user('node-exporter').with_home('/srv/ne') }
      end

      context 'with a mirror' do
        let(:params) { { source_url: 'https://mirror.example.org/node_exporter' } }

        it {
          is_expected.to contain_archive("/tmp/#{asset}")
            .with(source: "https://mirror.example.org/node_exporter/#{asset}", checksum_verify: true)
        }
      end

      context 'with an unknown version and no checksum' do
        let(:params) { { version: '9.9.9' } }

        it { is_expected.to compile.and_raise_error(%r{no sha256 digest known for node_exporter-9\.9\.9\.linux-amd64\.tar\.gz}) }
      end

      context 'with an unknown version and an explicit checksum' do
        let(:params) { { version: '9.9.9', checksum: 'abc123' } }

        it { is_expected.to contain_archive('/tmp/node_exporter-9.9.9.linux-amd64.tar.gz').with(checksum: 'abc123', checksum_verify: true) }
      end

      context 'without user and service management' do
        let(:params) { { manage_user: false, manage_service: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_user('node-exporter') }
        it { is_expected.not_to contain_systemd__manage_unit('node_exporter.service') }
      end
    end
  end
end
