# frozen_string_literal: true

require 'spec_helper'

describe 'node_exporter::collector::puppet' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'with default parameters' do
        it { is_expected.to compile.with_all_deps }

        it {
          pyyaml = (os_facts[:os]['family'] == 'Debian') ? 'python3-yaml' : 'python3-pyyaml'
          is_expected.to contain_package(pyyaml)
          is_expected.to contain_package('python3')
        }

        it {
          is_expected.to contain_node_exporter__textfile('puppet_agent')
            .with_on_calendar('*:0/5')
            .with_script_content(%r{class PuppetAgentCollector})
            .with_command([
                            '/usr/bin/python3', '/usr/local/lib/node_exporter/collectors/puppet_agent',
                            '--summary', '/opt/puppetlabs/puppet/public/last_run_summary.yaml',
                            '--report', '/opt/puppetlabs/puppet/cache/state/last_run_report.yaml',
                            '--state-dir', '/opt/puppetlabs/puppet/cache/state'
                          ])
        }

        it { is_expected.to contain_file('/usr/local/lib/node_exporter/collectors/puppet_agent').with_mode('0755') }
        it { is_expected.to contain_systemd__manage_unit('node_exporter-textfile-puppet_agent.timer').with(enable: true, active: true) }
      end

      context 'without managing python' do
        let(:params) { { manage_python: false } }

        it { is_expected.not_to contain_package('python3') }
      end
    end
  end
end
