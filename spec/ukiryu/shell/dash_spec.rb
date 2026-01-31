# frozen_string_literal: true

require 'spec_helper'
require_relative 'unix_base_shared_examples'

RSpec.describe Ukiryu::Shell::Dash do
  let(:shell) { described_class.new }

  describe '#name' do
    it 'returns :dash' do
      expect(shell.name).to eq(:dash)
    end
  end

  describe '#shell_command' do
    it 'returns "dash"' do
      expect(shell.shell_command).to eq('dash')
    end
  end

  # Include shared Unix shell behaviors (Dash is POSIX-compliant like bash)
  it_behaves_like 'a Unix shell' do
    let(:subject) { shell }
  end

  it_behaves_like 'a Unix shell with headless support' do
    let(:subject) { shell }
  end

  # Dash-specific tests
  describe 'unique Dash behaviors' do
    it 'has proper shell detection' do
      expect(shell.name).to eq(:dash)
      expect(shell.shell_command).to eq('dash')
    end

    context 'when dash is available on the system' do
      it 'can find dash executable' do
        skip 'dash not available on system' unless system('which dash > /dev/null 2>&1')

        expect { shell.shell_executable }.not_to raise_error
        expect(shell.shell_executable).to include('dash')
      end
    end
  end
end
