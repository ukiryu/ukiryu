# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Models::ExecutionReport do
  let(:register_path) { '/dummy/register/path' }

  describe 'StageMetrics' do
    let(:stage) { Ukiryu::Models::StageMetrics.new(name: 'test_stage') }

    describe '#initialize' do
      it 'creates a new stage with default values' do
        expect(stage.name).to eq('test_stage')
        expect(stage.duration).to eq(0.0)
        expect(stage.formatted_duration).to eq('')
        expect(stage.memory_before).to eq(0)
        expect(stage.memory_after).to eq(0)
        expect(stage.memory_delta).to eq(0)
        expect(stage.success).to be(true)
        expect(stage.error).to eq('')
      end

      it 'creates a new stage with custom values' do
        custom_stage = Ukiryu::Models::StageMetrics.new(
          name: 'custom_stage',
          duration: 1.5,
          formatted_duration: '1.5s',
          memory_before: 1000,
          memory_after: 2000,
          memory_delta: 1000,
          success: false,
          error: 'Test error'
        )

        expect(custom_stage.name).to eq('custom_stage')
        expect(custom_stage.duration).to eq(1.5)
        expect(custom_stage.formatted_duration).to eq('1.5s')
        expect(custom_stage.memory_before).to eq(1000)
        expect(custom_stage.memory_after).to eq(2000)
        expect(custom_stage.memory_delta).to eq(1000)
        expect(custom_stage.success).to be(false)
        expect(custom_stage.error).to eq('Test error')
      end
    end

    describe '#start!' do
      it 'records the start time and memory before' do
        stage.start!

        expect(stage.instance_variable_get(:@start_time)).to be_a(Time)
        # Memory detection is Unix-only (uses `ps` command)
        # Works on Ubuntu containers but not on Alpine (BusyBox ps doesn't support it)
        # In Docker/CI, may be 0 or an actual value
        expect(stage.memory_before).to be_a(Integer)
        expect(stage.memory_before).to be >= 0
        expect(stage.memory_after).to eq(0)
      end

      it 'returns self for chaining' do
        result = stage.start!
        expect(result).to eq(stage)
      end
    end

    describe '#finish!' do
      before { stage.start! }

      it 'calculates duration and memory delta' do
        # Simulate some memory usage
        stage.finish!

        expect(stage.duration).to be_a(Float)
        expect(stage.duration).to be >= 0
        expect(stage.formatted_duration).to be_a(String)
        # Memory detection is Unix-only (uses `ps` command)
        # Works on Ubuntu containers but not on Alpine (BusyBox ps doesn't support it)
        # In Docker/CI, may be 0 or an actual value
        expect(stage.memory_after).to be_a(Integer)
        expect(stage.memory_after).to be >= 0
        # Memory delta is calculated (may be negative due to GC)
        expect(stage.memory_delta).to be_a(Integer)
        # Verify delta calculation is correct
        expect(stage.memory_delta).to eq(stage.memory_after - stage.memory_before)
      end

      it 'marks the stage as successful by default' do
        stage.finish!
        expect(stage.success).to be(true)
        expect(stage.error).to eq('')
      end

      it 'marks the stage as failed when success: false is passed' do
        stage.finish!(success: false, error: 'Test failure')
        expect(stage.success).to be(false)
        expect(stage.error).to eq('Test failure')
      end
    end
  end

  describe 'RunEnvironment' do
    describe '.collect' do
      let(:env) { Ukiryu::Models::RunEnvironment.collect }

      it 'collects system environment information' do
        expect(env.hostname).to be_a(String)
        expect(env.platform).to be_a(String)
        expect(env.os_version).to be_a(String)
        expect(env.shell).to be_a(String)
        expect(env.ruby_version).to be_a(String)
        expect(env.ukiryu_version).to eq(Ukiryu::VERSION)
        expect(env.cpu_count).to be_a(Integer)
        expect(env.cpu_count).to be > 0
        expect(env.total_memory).to be_a(Integer)
        expect(env.working_directory).to be_a(String)
      end

      it 'returns a RunEnvironment instance' do
        expect(env).to be_a(Ukiryu::Models::RunEnvironment)
      end
    end

    describe '#initialize' do
      it 'creates a new environment with custom values' do
        custom_env = Ukiryu::Models::RunEnvironment.new(
          hostname: 'test-host',
          platform: 'test-platform',
          os_version: '1.0',
          shell: '/bin/test',
          shell_version: '1.0',
          ruby_version: '3.0.0',
          ukiryu_version: '0.1.0',
          cpu_count: 8,
          total_memory: 16,
          working_directory: '/test'
        )

        expect(custom_env.hostname).to eq('test-host')
        expect(custom_env.platform).to eq('test-platform')
        expect(custom_env.os_version).to eq('1.0')
        expect(custom_env.shell).to eq('/bin/test')
        expect(custom_env.shell_version).to eq('1.0')
        expect(custom_env.ruby_version).to eq('3.0.0')
        expect(custom_env.ukiryu_version).to eq('0.1.0')
        expect(custom_env.cpu_count).to eq(8)
        expect(custom_env.total_memory).to eq(16)
        expect(custom_env.working_directory).to eq('/test')
      end
    end
  end

  describe 'ExecutionReport' do
    let(:stage1) { Ukiryu::Models::StageMetrics.new(name: 'stage1') }
    let(:stage2) { Ukiryu::Models::StageMetrics.new(name: 'stage2') }
    let(:env) { Ukiryu::Models::RunEnvironment.collect }

    describe '#initialize' do
      it 'creates a new report with all stages' do
        report = Ukiryu::Models::ExecutionReport.new(
          tool_resolution: stage1,
          command_building: stage2,
          execution: stage1,
          response_building: stage2,
          run_environment: env,
          timestamp: '2024-01-01T00:00:00Z'
        )

        expect(report.tool_resolution).to eq(stage1)
        expect(report.command_building).to eq(stage2)
        expect(report.execution).to eq(stage1)
        expect(report.response_building).to eq(stage2)
        expect(report.run_environment).to eq(env)
        expect(report.timestamp).to eq('2024-01-01T00:00:00Z')
      end
    end

    describe '#calculate_total' do
      let(:report) do
        # Create stages with specific durations
        s1 = Ukiryu::Models::StageMetrics.new(name: 's1', duration: 0.1)
        s2 = Ukiryu::Models::StageMetrics.new(name: 's2', duration: 0.2)
        s3 = Ukiryu::Models::StageMetrics.new(name: 's3', duration: 0.3)
        s4 = Ukiryu::Models::StageMetrics.new(name: 's4', duration: 0.4)

        Ukiryu::Models::ExecutionReport.new(
          tool_resolution: s1,
          command_building: s2,
          execution: s3,
          response_building: s4,
          run_environment: env,
          timestamp: '2024-01-01T00:00:00Z'
        )
      end

      it 'calculates the total duration from all stages' do
        report.calculate_total
        expect(report.total_duration).to eq(1.0) # 0.1 + 0.2 + 0.3 + 0.4
        expect(report.formatted_total_duration).to eq('1.0s')
      end
    end

    describe '#all_stages' do
      let(:report) do
        Ukiryu::Models::ExecutionReport.new(
          tool_resolution: stage1,
          command_building: stage2,
          execution: nil, # Test nil handling
          response_building: stage1,
          run_environment: env,
          timestamp: '2024-01-01T00:00:00Z'
        )
      end

      it 'returns all non-nil stages' do
        stages = report.all_stages
        expect(stages).to eq([stage1, stage2, stage1])
      end
    end

    describe 'serialization' do
      it 'serializes to YAML correctly' do
        report = Ukiryu::Models::ExecutionReport.new(
          tool_resolution: Ukiryu::Models::StageMetrics.new(name: 'tool_resolution', duration: 0.1),
          command_building: Ukiryu::Models::StageMetrics.new(name: 'command_building', duration: 0.2),
          execution: Ukiryu::Models::StageMetrics.new(name: 'execution', duration: 0.3),
          response_building: Ukiryu::Models::StageMetrics.new(name: 'response_building', duration: 0.4),
          run_environment: env,
          timestamp: '2024-01-01T00:00:00Z'
        )

        yaml = report.to_yaml
        expect(yaml).to include('tool_resolution:')
        expect(yaml).to include('command_building:')
        expect(yaml).to include('execution:')
        expect(yaml).to include('response_building:')
        expect(yaml).to include('run_environment:')
      end
    end
  end
end
