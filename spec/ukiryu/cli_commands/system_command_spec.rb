# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Ukiryu::CliCommands::SystemCommand do
  let(:output) { StringIO.new }
  let(:options) { {} }

  before do
    # Reset shell detection state
    Ukiryu::Shell.reset
    Ukiryu::Config.reset!
  end

  after do
    # Clean up
    Ukiryu::Shell.reset
    Ukiryu::Config.reset!
  end

  describe '#run' do
    context 'with no subcommand' do
      it 'lists shells' do
        command = described_class.new(options)

        # Should not raise any errors
        expect { command.run }.not_to raise_error
      end
    end

    context 'with "shells" subcommand' do
      it 'lists available shells without errors' do
        command = described_class.new(options)

        expect { command.run('shells') }.not_to raise_error
      end
    end

    context 'with invalid subcommand' do
      it 'exits with error message' do
        command = described_class.new(options)

        expect { command.run('invalid') }.to raise_error(Thor::Error)
      end
    end
  end

  describe 'shell listing behavior' do
    it 'detects available shells on the system' do
      shells = Ukiryu::Shell.available_shells

      expect(shells).to be_an(Array)
      expect(shells).to all(be_a(Symbol))
    end

    it 'provides all valid shell types (platform groups + individual shells)' do
      shells = Ukiryu::Shell.all_valid

      expect(shells).to include(:unix, :windows, :powershell, :bash, :zsh, :fish, :sh)
    end

    it 'provides platform-specific shell groups' do
      shells = Ukiryu::Shell.valid_for_platform

      expect(shells).to be_an(Array)
      if Ukiryu::Platform.windows?
        expect(shells).to include(:windows, :powershell, :unix)
      else
        expect(shells).to include(:unix, :powershell)
      end
    end
  end

  describe 'shell availability detection' do
    it 'can check if bash is available' do
      result = Ukiryu::Shell.available?(:bash)

      expect(result).to be_a(TrueClass).or be_a(FalseClass)
    end

    it 'returns false for invalid shells' do
      expect(Ukiryu::Shell.available?(:invalid_shell)).to be(false)
    end

    it 'returns false for nil' do
      expect(Ukiryu::Shell.available?(nil)).to be(false)
    end
  end

  describe 'shell validation' do
    it 'validates known shell types' do
      expect(Ukiryu::Shell.valid?(:bash)).to be(true)
      expect(Ukiryu::Shell.valid?(:zsh)).to be(true)
      expect(Ukiryu::Shell.valid?(:fish)).to be(true)
      expect(Ukiryu::Shell.valid?(:sh)).to be(true)
      expect(Ukiryu::Shell.valid?(:powershell)).to be(true)
      expect(Ukiryu::Shell.valid?(:cmd)).to be(true)
    end

    it 'rejects invalid shell types' do
      expect(Ukiryu::Shell.valid?(:invalid)).to be(false)
      expect(Ukiryu::Shell.valid?(:nu)).to be(false)
      expect(Ukiryu::Shell.valid?(nil)).to be(false)
    end

    it 'converts valid shell strings to symbols' do
      expect(Ukiryu::Shell.from_string('bash')).to eq(:bash)
      expect(Ukiryu::Shell.from_string('zsh')).to eq(:zsh)
      expect(Ukiryu::Shell.from_string('PowerShell')).to eq(:powershell)
      expect(Ukiryu::Shell.from_string('BASH')).to eq(:bash)
    end

    it 'raises error for invalid shell strings' do
      expect do
        Ukiryu::Shell.from_string('invalid')
      end.to raise_error(ArgumentError, /Invalid shell/)
    end
  end
end
