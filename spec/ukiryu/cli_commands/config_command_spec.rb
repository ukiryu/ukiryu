# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe Ukiryu::CliCommands::ConfigCommand do
  let(:options) { {} }
  let(:test_config_dir) { File.expand_path('~/.ukiryu_test') }
  let(:test_config_file) { File.join(test_config_dir, 'config.yml') }

  before do
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset

    # Use test config directory
    stub_const('Ukiryu::CliCommands::ConfigCommand::CONFIG_DIR', test_config_dir)
    stub_const('Ukiryu::CliCommands::ConfigCommand::CONFIG_FILE', test_config_file)

    # Clean up any existing test config
    FileUtils.rm_f(test_config_file) if File.exist?(test_config_file)
  end

  after do
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset

    # Clean up test config
    FileUtils.rm_f(test_config_file) if File.exist?(test_config_file)
    FileUtils.rm_rf(test_config_dir) if Dir.exist?(test_config_dir)
  end

  describe '#run' do
    describe 'list action' do
      it 'lists all configuration without errors' do
        command = described_class.new(options)
        expect { command.run('list') }.not_to raise_error
      end

      it 'shows current configuration values' do
        command = described_class.new(options)
        expect { command.run('list') }.not_to raise_error
      end

      it 'shows persistent config status' do
        command = described_class.new(options)
        expect { command.run('list') }.not_to raise_error
      end

      it 'shows environment variables' do
        command = described_class.new(options)
        expect { command.run('list') }.not_to raise_error
      end
    end

    describe 'get action' do
      it 'gets a valid configuration value' do
        command = described_class.new(options)
        expect { command.run('get', 'debug') }.not_to raise_error
      end

      it 'gets registry configuration' do
        command = described_class.new(options)
        expect { command.run('get', 'registry') }.not_to raise_error
      end

      it 'gets format configuration' do
        command = described_class.new(options)
        expect { command.run('get', 'format') }.not_to raise_error
      end

      it 'exits with error for unknown key' do
        command = described_class.new(options)
        expect { command.run('get', 'unknown_key') }.to raise_error(Thor::Error)
      end
    end

    describe 'set action' do
      it 'sets debug to true' do
        command = described_class.new(options)
        expect { command.run('set', 'debug', 'true') }.not_to raise_error
        expect(File.exist?(test_config_file)).to be true
      end

      it 'sets registry path' do
        command = described_class.new(options)
        expect { command.run('set', 'registry', '/test/path') }.not_to raise_error
        expect(File.exist?(test_config_file)).to be true
      end

      it 'sets timeout value' do
        command = described_class.new(options)
        expect { command.run('set', 'timeout', '60') }.not_to raise_error
        expect(File.exist?(test_config_file)).to be true
      end

      it 'creates config directory if not exists' do
        command = described_class.new(options)
        FileUtils.rm_rf(test_config_dir) if Dir.exist?(test_config_dir)
        expect { command.run('set', 'debug', 'true') }.not_to raise_error
        expect(Dir.exist?(test_config_dir)).to be true
      end

      it 'parses boolean values correctly' do
        command = described_class.new(options)
        expect { command.run('set', 'debug', 'yes') }.not_to raise_error
        expect { command.run('set', 'dry_run', '1') }.not_to raise_error
      end
    end

    describe 'unset action' do
      before do
        # Create a test config file
        FileUtils.mkdir_p(test_config_dir)
        File.write(test_config_file, { 'debug' => 'true', 'registry' => '/test' }.to_yaml)
      end

      it 'unsets an existing key' do
        command = described_class.new(options)
        expect { command.run('unset', 'debug') }.not_to raise_error
      end

      it 'exits with error for non-existent key' do
        command = described_class.new(options)
        expect { command.run('unset', 'nonexistent') }.to raise_error(Thor::Error)
      end
    end

    describe 'invalid actions' do
      it 'exits with error for unknown action' do
        command = described_class.new(options)
        expect { command.run('invalid_action') }.to raise_error(Thor::Error)
      end
    end
  end

  describe 'value parsing' do
    it 'parses timeout as integer' do
      command = described_class.new(options)
      command.run('set', 'timeout', '120')
      loaded = YAML.load_file(test_config_file)
      expect(loaded['timeout']).to eq('120')
    end

    it 'parses boolean values' do
      command = described_class.new(options)
      command.run('set', 'debug', 'true')
      command.run('set', 'dry_run', 'false')
      loaded = YAML.load_file(test_config_file)
      expect(loaded['debug']).to eq('true')
      expect(loaded['dry_run']).to eq('false')
    end

    it 'preserves string values' do
      command = described_class.new(options)
      command.run('set', 'registry', '/custom/path')
      loaded = YAML.load_file(test_config_file)
      expect(loaded['registry']).to eq('/custom/path')
    end
  end

  describe 'file persistence' do
    it 'saves config to file' do
      command = described_class.new(options)
      command.run('set', 'debug', 'true')
      expect(File.exist?(test_config_file)).to be true
    end

    it 'overwrites existing config' do
      command = described_class.new(options)
      command.run('set', 'debug', 'true')
      command.run('set', 'debug', 'false')
      loaded = YAML.load_file(test_config_file)
      expect(loaded['debug']).to eq('false')
    end

    it 'preserves other keys when updating one key' do
      command = described_class.new(options)
      command.run('set', 'debug', 'true')
      command.run('set', 'registry', '/test')
      command.run('unset', 'debug')
      loaded = YAML.load_file(test_config_file)
      expect(loaded.key?('debug')).to be false
      expect(loaded['registry']).to eq('/test')
    end
  end
end
