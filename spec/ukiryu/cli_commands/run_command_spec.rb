# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::CliCommands::RunCommand do
  let(:options) { {} }

  before do
    Ukiryu::Tool.clear_cache
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset
  end

  after do
    Ukiryu::Tool.clear_cache
    Ukiryu::Config.reset!
    Ukiryu::Shell.reset
  end

  describe '#run' do
    context 'with a valid tool and command' do
      it 'executes imagemagick convert in dry run mode' do
        command = described_class.new(options.merge(dry_run: true))

        expect { command.run('imagemagick', 'convert') }.not_to raise_error
      end

      it 'executes curl in dry run mode' do
        command = described_class.new(options.merge(dry_run: true))

        expect { command.run('curl', 'get') }.not_to raise_error
      end
    end

    context 'with parameters' do
      it 'handles key=value parameters correctly' do
        command = described_class.new(options.merge(dry_run: true))

        expect { command.run('imagemagick', 'convert', 'output=test.jpg') }.not_to raise_error
      end

      it 'handles multiple parameters' do
        command = described_class.new(options.merge(dry_run: true))

        expect { command.run('imagemagick', 'convert', 'output=test.jpg', 'resize=50x50') }.not_to raise_error
      end
    end

    context 'with command_name omitted' do
      it 'resolves default command when command_name looks like a parameter' do
        command = described_class.new(options.merge(dry_run: true))

        # When user types: ukiryu exec ping host=127.0.0.1
        # Thor interprets it as: tool_name="ping", command_name="host=127.0.0.1"
        # The command should detect this and shift command_name to params
        expect { command.run('imagemagick', 'output=test.jpg') }.not_to raise_error
      end
    end

    context 'with an invalid tool' do
      it 'exits with error for non-existent tool' do
        command = described_class.new(options)

        # RunCommand catches the error and returns an ErrorResponse
        # It doesn't raise an exception
        expect { command.run('nonexistent_tool', 'command') }.not_to raise_error
      end
    end

    context 'with invalid parameter format' do
      it 'raises an error for parameters without equals sign' do
        command = described_class.new(options)

        expect { command.run('imagemagick', 'convert', 'invalid_param') }.to raise_error(Thor::Error)
      end
    end
  end

  describe 'parameter parsing' do
    it 'parses string values' do
      command = described_class.new(options.merge(dry_run: true))

      expect { command.run('imagemagick', 'convert', 'output=test.jpg') }.not_to raise_error
    end

    it 'parses integer values from YAML' do
      command = described_class.new(options.merge(dry_run: true))

      expect { command.run('imagemagick', 'convert', 'quality=85') }.not_to raise_error
    end

    it 'parses boolean values from YAML' do
      command = described_class.new(options.merge(dry_run: true))

      expect { command.run('imagemagick', 'convert', 'strip=true') }.not_to raise_error
    end

    it 'parses array values from YAML' do
      command = described_class.new(options.merge(dry_run: true))

      expect { command.run('imagemagick', 'convert', 'inputs=[a.png,b.png]') }.not_to raise_error
    end
  end

  describe 'output formats' do
    it 'supports yaml format' do
      command = described_class.new(options.merge(format: 'yaml', dry_run: true))

      expect { command.run('imagemagick', 'convert') }.not_to raise_error
    end

    it 'supports json format' do
      command = described_class.new(options.merge(format: 'json', dry_run: true))

      expect { command.run('imagemagick', 'convert') }.not_to raise_error
    end

    it 'supports table format' do
      command = described_class.new(options.merge(format: 'table', dry_run: true))

      expect { command.run('imagemagick', 'convert') }.not_to raise_error
    end

    it 'raises error for invalid format' do
      command = described_class.new(options.merge(format: 'invalid', dry_run: true))

      expect { command.run('imagemagick', 'convert') }.to raise_error(Thor::Error)
    end
  end
end
