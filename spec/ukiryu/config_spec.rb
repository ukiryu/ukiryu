# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Config do
  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe '.shell' do
    it 'returns nil by default' do
      expect(described_class.shell).to be_nil
    end

    it 'returns the configured shell value' do
      described_class.configure do |config|
        config.shell = :zsh
      end

      expect(described_class.shell).to eq(:zsh)
    end

    it 'converts string to symbol' do
      described_class.configure do |config|
        config.shell = 'bash'
      end

      expect(described_class.shell).to eq(:bash)
    end
  end

  describe '.shell=' do
    it 'sets the shell value' do
      described_class.configure do |config|
        config.shell = :fish
      end

      expect(described_class.shell).to eq(:fish)
    end

    it 'handles nil values' do
      described_class.configure do |config|
        config.shell = :bash
      end

      described_class.configure do |config|
        config.shell = nil
      end

      expect(described_class.shell).to be_nil
    end
  end

  describe 'shell configuration priority' do
    context 'with ENV variable' do
      before do
        ENV['UKIRYU_SHELL'] = 'zsh'
        described_class.reset! # Reset after setting ENV to pick up the new value
      end

      after do
        ENV.delete('UKIRYU_SHELL')
        described_class.reset!
      end

      it 'reads shell from UKIRYU_SHELL env var' do
        expect(described_class.shell).to eq(:zsh)
      end

      it 'allows CLI option to override ENV' do
        described_class.configure do |config|
          config.set_cli_option(:shell, :fish)
        end

        expect(described_class.shell).to eq(:fish)
      end
    end

    context 'with programmatic configuration' do
      it 'returns the configured shell' do
        described_class.configure do |config|
          config.shell = :fish
        end

        expect(described_class.shell).to eq(:fish)
      end

      it 'allows CLI option to override programmatic config' do
        described_class.configure do |config|
          config.shell = :bash
          config.set_cli_option(:shell, :zsh)
        end

        expect(described_class.shell).to eq(:zsh)
      end
    end
  end

  describe '#to_h' do
    it 'includes shell in the hash' do
      described_class.configure do |config|
        config.shell = :zsh
      end

      hash = described_class.to_h
      expect(hash[:shell]).to eq(:zsh)
    end

    it 'includes nil when shell is not set' do
      hash = described_class.to_h
      expect(hash[:shell]).to be_nil
    end
  end
end
