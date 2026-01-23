# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Ukiryu::Logger do
  let(:output) { StringIO.new }
  let(:logger) { described_class.new(output: output) }

  before do
    # Reset config before each test
    Ukiryu::Config.reset!
  end

  after do
    # Reset config after each test
    Ukiryu::Config.reset!
  end

  describe '#initialize' do
    it 'creates a logger with default output' do
      logger = described_class.new
      expect(logger.output).to eq($stderr)
    end

    it 'creates a logger with custom output' do
      expect(logger.output).to eq(output)
    end

    context 'when debug mode is enabled via Config' do
      before do
        Ukiryu::Config.configure do |config|
          config.debug = true
        end
      end

      it 'detects debug mode from Config' do
        logger_with_debug = described_class.new(output: output)
        expect(logger_with_debug.debug_enabled?).to be(true)
      end

      it 'tries to load Paint gem when debug mode is enabled' do
        logger_with_debug = described_class.new(output: output)
        expect(logger_with_debug.paint_available).to be_a(TrueClass).or be_a(FalseClass)
      end
    end

    context 'when debug mode is disabled' do
      before do
        Ukiryu::Config.configure do |config|
          config.debug = false
        end
      end

      it 'does not enable debug mode' do
        logger_without_debug = described_class.new(output: output)
        expect(logger_without_debug.debug_enabled?).to be(false)
      end
    end
  end

  describe 'debug sections with bordered style' do
    before do
      Ukiryu::Config.configure do |config|
        config.debug = true
      end
    end

    describe '#debug_section_ukiryu_options' do
      it 'outputs CLI options with bordered style' do
        logger_with_debug = described_class.new(output: output)
        options = {
          format: :yaml,
          debug: true,
          dry_run: false
        }

        logger_with_debug.debug_section_ukiryu_options(options)
        output.rewind
        content = output.read

        expect(content).to include('Ukiryu CLI Options')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('format')
        expect(content).to include('debug')
        expect(content).to include('dry_run')
      end
    end

    describe '#debug_section_tool_resolution' do
      it 'outputs tool resolution with bordered style' do
        logger_with_debug = described_class.new(output: output)

        logger_with_debug.debug_section_tool_resolution(
          identifier: 'ping',
          platform: :macos,
          shell: :bash,
          all_tools: %w[ping_bsd ping_gnu imagemagick],
          selected_tool: 'ping_bsd',
          executable: '/sbin/ping'
        )

        output.rewind
        content = output.read

        expect(content).to include('Tool Resolution: ping')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('Platform')
        expect(content).to include('macos')
        expect(content).to include('Shell')
        expect(content).to include('bash')
        expect(content).to include('Available Tools')
        expect(content).to include('ping_bsd')
        expect(content).to include('ping_gnu')
        expect(content).to include('Selected')
        expect(content).to include('Executable')
        expect(content).to include('/sbin/ping')
      end
    end

    describe '#debug_section_tool_not_found' do
      it 'outputs tool not found with bordered style' do
        logger_with_debug = described_class.new(output: output)

        logger_with_debug.debug_section_tool_not_found(
          identifier: 'nonexistent',
          platform: :macos,
          shell: :bash,
          all_tools: %w[ping_bsd ping_gnu]
        )

        output.rewind
        content = output.read

        expect(content).to include('Tool Resolution: nonexistent')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('Tool not found')
      end
    end

    describe '#debug_section_structured_options' do
      it 'outputs structured options with bordered style' do
        logger_with_debug = described_class.new(output: output)

        options_class = Class.new do
          attr_accessor :host, :count

          def initialize
            @host = '127.0.0.1'
            @count = 1
          end
        end

        options = options_class.new

        logger_with_debug.debug_section_structured_options('ping', 'ping', options)

        output.rewind
        content = output.read

        expect(content).to include('Structured Options (ping ping)')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('host')
        expect(content).to include('127.0.0.1')
        expect(content).to include('count')
        expect(content).to include('1')
      end
    end

    describe '#debug_section_shell_command' do
      it 'outputs shell command with bordered style' do
        logger_with_debug = described_class.new(output: output)

        logger_with_debug.debug_section_shell_command(
          executable: '/sbin/ping',
          full_command: '/sbin/ping -c 1 127.0.0.1'
        )

        output.rewind
        content = output.read

        expect(content).to include('Shell Command')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('Executable')
        expect(content).to include('/sbin/ping')
        expect(content).to include('Full Command')
        expect(content).to include('/sbin/ping -c 1 127.0.0.1')
      end

      it 'outputs environment variables when provided' do
        logger_with_debug = described_class.new(output: output)

        logger_with_debug.debug_section_shell_command(
          executable: '/bin/echo',
          full_command: '/bin/echo hello',
          env_vars: { 'TEST_VAR' => 'test_value' }
        )

        output.rewind
        content = output.read

        expect(content).to include('Environment Variables')
        expect(content).to include('TEST_VAR=test_value')
      end
    end

    describe '#debug_section_raw_response' do
      it 'outputs raw response with bordered style' do
        logger_with_debug = described_class.new(output: output)

        logger_with_debug.debug_section_raw_response(
          stdout: 'Hello, World!',
          stderr: '',
          exit_code: 0
        )

        output.rewind
        content = output.read

        expect(content).to include('Raw Command Response')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('Exit Code')
        expect(content).to include('0')
        expect(content).to include('STDOUT')
        expect(content).to include('Hello, World!')
      end

      it 'outputs stderr when present' do
        logger_with_debug = described_class.new(output: output)

        logger_with_debug.debug_section_raw_response(
          stdout: '',
          stderr: 'Error occurred',
          exit_code: 1
        )

        output.rewind
        content = output.read

        expect(content).to include('STDERR')
        expect(content).to include('Error occurred')
      end
    end

    describe '#debug_section_structured_response' do
      it 'outputs structured response with bordered style' do
        logger_with_debug = described_class.new(output: output)

        response = double('Response', to_yaml: "status: success\nexit_code: 0")

        logger_with_debug.debug_section_structured_response(response)

        output.rewind
        content = output.read

        expect(content).to include('Structured Response')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('status: success')
        expect(content).to include('exit_code: 0')
      end
    end

    describe '#debug_section_execution_report' do
      it 'outputs execution report with bordered style' do
        logger_with_debug = described_class.new(output: output)

        stage1 = Ukiryu::Models::StageMetrics.new(
          name: 'tool_resolution',
          duration: 0.05,
          formatted_duration: '50ms',
          memory_delta: 1024
        )

        stage2 = Ukiryu::Models::StageMetrics.new(
          name: 'execution',
          duration: 0.01,
          formatted_duration: '10ms',
          memory_delta: 512
        )

        env = Ukiryu::Models::RunEnvironment.new(
          hostname: 'test-host',
          platform: 'test-platform',
          os_version: '1.0',
          shell: '/bin/bash',
          ruby_version: '3.0.0',
          ukiryu_version: '0.1.0',
          cpu_count: 8,
          total_memory: 16,
          working_directory: '/test'
        )

        report = Ukiryu::Models::ExecutionReport.new(
          tool_resolution: stage1,
          command_building: stage1,
          execution: stage2,
          response_building: stage1,
          run_environment: env,
          timestamp: '2024-01-01T00:00:00Z'
        )

        logger_with_debug.debug_section_execution_report(report)

        output.rewind
        content = output.read

        expect(content).to include('Execution Report')
        expect(content).to include('┌─')
        expect(content).to include('└─')
        expect(content).to include('Run Environment')
        expect(content).to include('Stage Timings')
        expect(content).to include('tool_resolution')
        expect(content).to include('execution')
      end
    end
  end

  describe 'debug mode' do
    context 'when debug mode is disabled' do
      before do
        Ukiryu::Config.configure do |config|
          config.debug = false
        end
      end

      it 'does not output debug sections' do
        logger_no_debug = described_class.new(output: output)
        logger_no_debug.debug_section_ukiryu_options({})

        output.rewind
        content = output.read

        expect(content).to be_empty
      end
    end

    context 'when debug mode is enabled' do
      before do
        Ukiryu::Config.configure do |config|
          config.debug = true
        end
      end

      it 'outputs debug sections' do
        logger_with_debug = described_class.new(output: output)
        logger_with_debug.debug_section_ukiryu_options({ test: true })

        output.rewind
        content = output.read

        expect(content).not_to be_empty
      end
    end
  end

  describe 'accessors' do
    it 'provides access to output stream' do
      expect(logger.output).to eq(output)
    end

    it 'provides access to paint_available flag' do
      expect(logger.paint_available).to be_a(TrueClass).or be_a(FalseClass)
    end
  end
end
