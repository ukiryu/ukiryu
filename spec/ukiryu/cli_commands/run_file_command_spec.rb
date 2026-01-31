# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'tempfile'

RSpec.describe Ukiryu::CliCommands::RunFileCommand do
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
    context 'with a valid request file' do
      let(:request_file) do
        file = Tempfile.new(['ukiryu_request', '.yaml'])
        file.write(<<~YAML)
          tool: imagemagick
          command: convert
          arguments:
            inputs:
              - spec/fixtures/input.png
            output: spec/fixtures/output.jpg
        YAML
        file.flush # Ensure content is written
        file.path # Return path without closing
      end

      it 'executes the request without errors in dry run mode' do
        command = described_class.new(options.merge(dry_run: true))

        expect { command.run(request_file) }.not_to raise_error
      end

      it 'validates the request structure' do
        command = described_class.new(options.merge(dry_run: true))

        expect { command.run(request_file) }.not_to raise_error
      end
    end

    context 'with an invalid request file' do
      let(:request_file) do
        file = Tempfile.new(['ukiryu_request', '.yaml'])
        file.write(<<~YAML)
          invalid: yaml
          missing: fields
        YAML
        file.flush
        file.path
      end

      it 'validates the request and raises error for missing tool field' do
        command = described_class.new(options)

        # The validate_request! raises RuntimeError for invalid structure
        expect { command.run(request_file) }.to raise_error(RuntimeError, /tool/)
      end
    end

    context 'with a non-existent file' do
      it 'raises an error for missing file' do
        command = described_class.new(options)

        expect { command.run('/nonexistent/file.yaml') }.to raise_error(Thor::Error)
      end
    end

    context 'with invalid YAML' do
      let(:request_file) do
        file = Tempfile.new(['ukiryu_request', '.yaml'])
        file.write(<<~YAML)
          tool: imagemagick
          command: convert
          arguments:
            - invalid
            - yaml
              structure
        YAML
        file.flush
        file.path
      end

      it 'validates the request and raises error for invalid arguments structure' do
        command = described_class.new(options)

        # The validate_request! raises RuntimeError for invalid structure
        expect { command.run(request_file) }.to raise_error(RuntimeError, /arguments/)
      end
    end
  end

  describe 'output formats' do
    let(:request_file) do
      file = Tempfile.new(['ukiryu_request', '.yaml'])
      file.write(<<~YAML)
        tool: imagemagick
        command: convert
        arguments:
          inputs:
            - spec/fixtures/input.png
          output: spec/fixtures/output.jpg
      YAML
      file.flush
      file.path
    end

    it 'supports yaml format' do
      command = described_class.new(options.merge(format: 'yaml', dry_run: true))

      expect { command.run(request_file) }.not_to raise_error
    end

    it 'supports json format' do
      command = described_class.new(options.merge(format: 'json', dry_run: true))

      expect { command.run(request_file) }.not_to raise_error
    end

    it 'supports table format' do
      command = described_class.new(options.merge(format: 'table', dry_run: true))

      expect { command.run(request_file) }.not_to raise_error
    end
  end
end
