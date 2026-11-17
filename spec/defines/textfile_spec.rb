# frozen_string_literal: true

require 'spec_helper'

describe 'node_exporter::textfile' do
  let(:title) { 'apt' }

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'with a command' do
        let(:params) { { command: ['/usr/local/bin/apt_info.py', '--max-age', '1 h'] } }

        it { is_expected.to compile.with_all_deps }

        it {
          service = catalogue.resource('Systemd::Manage_unit', 'node_exporter-textfile-apt.service')
          expect(service[:service_entry]['Type']).to eq('oneshot')
          expect(service[:service_entry]['User']).to eq('root')
          expect(service[:service_entry]['ExecStart'])
            .to eq("/bin/sh -c '/usr/local/bin/apt_info.py --max-age 1\\ h > /var/lib/node_exporter/textfile/.apt.prom.tmp'")
          expect(service[:service_entry]['ExecStartPost'])
            .to eq('/bin/mv -f /var/lib/node_exporter/textfile/.apt.prom.tmp /var/lib/node_exporter/textfile/apt.prom')
          expect(service[:service_entry]['ProtectSystem']).to eq('strict')
          expect(service[:service_entry]['ReadWritePaths']).to eq(['/var/lib/node_exporter/textfile'])
        }

        it {
          is_expected.to contain_systemd__manage_unit('node_exporter-textfile-apt.timer')
            .with(enable: true, active: true)
            .with_timer_entry('OnCalendar' => '*:0/5', 'RandomizedDelaySec' => '30', 'Persistent' => true)
        }

        it { is_expected.not_to contain_file('/usr/local/lib/node_exporter/collectors/apt') }
      end

      context 'with a script' do
        let(:params) { { script_content: "#!/bin/sh\necho 'x 1'\n", on_calendar: 'hourly' } }

        it {
          is_expected.to contain_file('/usr/local/lib/node_exporter/collectors/apt')
            .with(ensure: 'file', owner: 'root', mode: '0755', content: "#!/bin/sh\necho 'x 1'\n")
        }

        it {
          service = catalogue.resource('Systemd::Manage_unit', 'node_exporter-textfile-apt.service')
          expect(service[:service_entry]['ExecStart']).to match(%r{\A/bin/sh -c '/usr/local/lib/node_exporter/collectors/apt > })
        }

        it { is_expected.to contain_systemd__manage_unit('node_exporter-textfile-apt.timer').with_timer_entry('OnCalendar' => 'hourly', 'RandomizedDelaySec' => '30', 'Persistent' => true) }
      end

      context 'next to the node_exporter class with its own textfile directory' do
        let(:pre_condition) { "class { 'node_exporter': textfile_directory => '/srv/prom' }" }
        let(:params) { { command: ['/bin/true'] } }

        it {
          service = catalogue.resource('Systemd::Manage_unit', 'node_exporter-textfile-apt.service')
          expect(service[:service_entry]['ExecStartPost']).to eq('/bin/mv -f /srv/prom/.apt.prom.tmp /srv/prom/apt.prom')
          expect(service[:service_entry]['ReadWritePaths']).to eq(['/srv/prom'])
        }
      end

      context 'with ensure absent' do
        let(:params) { { ensure: 'absent' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_systemd__manage_unit('node_exporter-textfile-apt.timer').with(ensure: 'absent', enable: false, active: false) }
        it { is_expected.to contain_file('/var/lib/node_exporter/textfile/apt.prom').with_ensure('absent') }
      end

      context 'without command and script' do
        it { is_expected.to compile.and_raise_error(%r{set command or script_content}) }
      end

      context 'with an invalid name' do
        let(:title) { 'Bad-Name' }
        let(:params) { { command: ['/bin/true'] } }

        it { is_expected.to compile.and_raise_error(%r{must be lower-case letters}) }
      end
    end
  end
end
