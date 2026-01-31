# frozen_string_literal: true

require 'spec_helper'
require_relative 'unix_base_shared_examples'

RSpec.describe Ukiryu::Shell::Bash do
  let(:shell) { described_class.new }

  describe '#name' do
    it 'returns :bash' do
      expect(shell.name).to eq(:bash)
    end
  end

  describe '#shell_command' do
    it 'returns "bash"' do
      expect(shell.shell_command).to eq('bash')
    end
  end

  # Include shared Unix shell behaviors
  it_behaves_like 'a Unix shell' do
    let(:subject) { shell }
  end

  it_behaves_like 'a Unix shell with macOS headless support' do
    let(:subject) { shell }
  end

  # Bash-specific tests
  describe 'unique Bash behaviors' do
    it 'has proper shell detection' do
      expect(shell.name).to eq(:bash)
      expect(shell.shell_command).to eq('bash')
    end

    context 'when bash is available on the system' do
      it 'can find bash executable' do
        skip 'bash not available on system' unless system('which bash > /dev/null 2>&1')

        expect { shell.shell_executable }.not_to raise_error
        expect(shell.shell_executable).to include('bash')
      end
    end
  end
end
