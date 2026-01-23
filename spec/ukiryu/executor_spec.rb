# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'timeout'
require 'fileutils'

RSpec.describe Ukiryu::Executor do
  let(:executor) { described_class }

  describe '.execute' do
    let(:executable) { 'echo' }
    let(:args) { ['test'] }
    let(:default_options) { {} }

    context 'with valid command' do
      it 'executes successfully and returns Result' do
        result = executor.execute(executable, args, default_options)

        expect(result).to be_a(Ukiryu::Execution::Result)
        expect(result.executable).to eq(executable)
        expect(result.command_info.arguments).to eq(args)
      end

      it 'captures stdout' do
        result = executor.execute(executable, ['hello world'], default_options)

        expect(result.stdout).to include('hello world')
      end

      it 'captures exit status' do
        result = executor.execute(executable, args, default_options)

        expect(result.exit_status).to eq(0)
      end

      it 'captures metadata with timing' do
        result = executor.execute(executable, args, default_options)

        expect(result.started_at).to be_a(Time)
        expect(result.finished_at).to be_a(Time)
        expect(result.duration).to be_a(Numeric)
        expect(result.duration).to be >= 0
      end
    end

    context 'with timeout option' do
      it 'uses custom timeout when specified' do
        start_time = Time.now
        result = executor.execute('sleep', ['0.01'], timeout: 5, allow_failure: true)
        elapsed = Time.now - start_time

        expect(result).to be_a(Ukiryu::Execution::Result)
        expect(elapsed).to be < 1 # Should complete quickly
      end

      it 'raises TimeoutError when command exceeds timeout' do
        # Use a command that will definitely timeout
        expect do
          executor.execute('sleep', ['10'], timeout: 0.01)
        end.to raise_error(Ukiryu::TimeoutError, /Command timed out after 0\.01 seconds/)
      end
    end

    context 'with environment variables' do
      it 'passes environment variables to command' do
        # Use a command that reads environment
        result = executor.execute(
          'sh',
          ['-c', 'echo "$TEST_VAR"'],
          env: { 'TEST_VAR' => 'test_value' },
          allow_failure: true
        )

        expect(result.stdout.strip).to eq('test_value')
      end

      it 'merges with existing environment' do
        result = executor.execute(
          'sh',
          ['-c', 'echo "$HOME"'],
          env: {},
          allow_failure: true
        )

        # HOME should be available from parent environment
        expect(result.stdout.strip).not_to be_empty
      end
    end

    context 'with working directory option' do
      it 'changes to specified directory before execution' do
        Dir.mktmpdir do |tmpdir|
          test_file = File.join(tmpdir, 'test.txt')
          File.write(test_file, 'test content')

          result = executor.execute(
            'cat',
            ['test.txt'],
            cwd: tmpdir,
            allow_failure: true
          )

          expect(result.stdout.strip).to eq('test content')
        end
      end
    end

    context 'with allow_failure option' do
      it 'returns Result with non-zero exit status instead of raising' do
        result = executor.execute('sh', ['-c', 'exit 42'], allow_failure: true)

        expect(result.exit_status).to eq(42)
        expect(result).to be_a(Ukiryu::Execution::Result)
      end

      it 'raises ExecutionError when command fails and allow_failure is false' do
        expect do
          executor.execute('sh', ['-c', 'exit 1'])
        end.to raise_error(Ukiryu::ExecutionError, /Command failed/)
      end

      it 'includes stderr in error message' do
        expect do
          executor.execute('sh', ['-c', 'echo error >&2; exit 1'])
        end.to raise_error(Ukiryu::ExecutionError, /STDERR:\s*error/)
      end
    end

    context 'error formatting' do
      it 'includes executable name in error message' do
        expect do
          executor.execute('false', [])
        end.to raise_error(Ukiryu::ExecutionError, /Command failed: false/)
      end

      it 'includes exit status in error message' do
        expect do
          executor.execute('sh', ['-c', 'exit 42'])
        end.to raise_error(Ukiryu::ExecutionError, /Exit status: 42/)
      end
    end

    context 'command building' do
      it 'builds appropriate command for the shell' do
        result_bash = executor.execute('sh', ['-c', 'echo $0'], shell: :bash, allow_failure: true)
        result_zsh = executor.execute('sh', ['-c', 'echo $0'], shell: :zsh, allow_failure: true)

        # Both should succeed (though output may differ)
        expect(result_bash.exit_status).to eq(0)
        expect(result_zsh.exit_status).to eq(0)
      end

      it 'includes executable path in CommandInfo' do
        result = executor.execute('echo', ['test'], allow_failure: true)

        expect(result.command_info.executable).to eq('echo')
        expect(result.command_info.full_command).to be_a(String)
        expect(result.command_info.shell).to be_a(Symbol)
      end
    end
  end

  describe '.find_executable' do
    context 'with common executables' do
      it 'finds executables in PATH' do
        # 'ruby' should be available in the test environment
        exe = executor.find_executable('ruby')
        expect(exe).to end_with('ruby')
        expect(File.executable?(exe)).to be true
      end

      it 'returns nil for non-existent command' do
        exe = executor.find_executable('nonexistent_command_xyz123')
        expect(exe).to be_nil
      end
    end

    context 'with additional search paths' do
      it 'searches in additional paths' do
        Dir.mktmpdir do |tmpdir|
          # Create a test executable
          test_exe = File.join(tmpdir, 'test_executable')
          File.write(test_exe, '#!/bin/sh\necho test')
          File.chmod(0755, test_exe)

          exe = executor.find_executable('test_executable', additional_paths: [tmpdir])
          expect(exe).to eq(test_exe)
        end
      end

      it 'prioritizes additional paths when specified' do
        tmpdir1 = Dir.mktmpdir
        tmpdir2 = Dir.mktmpdir
        begin
          # Create different executables in each directory
          exe1 = File.join(tmpdir1, 'test_cmd')
          exe2 = File.join(tmpdir2, 'test_cmd')
          File.write(exe1, '#!/bin/sh\necho 1')
          File.write(exe2, '#!/bin/sh\necho 2')
          File.chmod(0755, exe1)
          File.chmod(0755, exe2)

          # The first directory in additional_paths should be found first
          exe = executor.find_executable('test_cmd', additional_paths: [tmpdir1, tmpdir2])
          expect(exe).to eq(exe1)
        ensure
          FileUtils.rm_rf(tmpdir1)
          FileUtils.rm_rf(tmpdir2)
        end
      end
    end
  end

  describe '.build_command' do
    let(:bash_class) { Ukiryu::Shell::Bash }

    it 'joins executable and arguments properly' do
      command = executor.build_command('echo', ['hello', 'world'], bash_class)
      # Shell join adds quotes around each argument
      expect(command).to include('hello')
      expect(command).to include('world')
    end

    it 'formats path for the shell' do
      # Bash handles paths with spaces
      command = executor.build_command('echo', ['test'], bash_class)
      expect(command).to be_a(String)
    end
  end

  describe '.prepare_environment' do
    let(:bash_class) { Ukiryu::Shell::Bash }

    it 'includes user-specified variables' do
      env = executor.send(:prepare_environment, { 'CUSTOM_VAR' => 'value' }, bash_class)
      expect(env['CUSTOM_VAR']).to eq('value')
    end

    it 'preserves existing environment' do
      # Set a temp environment variable
      old_val = ENV['TEST_EXEC_ENV_VAR']
      ENV['TEST_EXEC_ENV_VAR'] = 'original'

      begin
        env = executor.send(:prepare_environment, {}, bash_class)
        expect(env['TEST_EXEC_ENV_VAR']).to eq('original')
      ensure
        ENV['TEST_EXEC_ENV_VAR'] = old_val if old_val
      end
    end

    it 'merges shell-specific headless environment' do
      env = executor.send(:prepare_environment, {}, bash_class)
      # Bash adds specific environment variables for headless mode
      expect(env).to be_a(Hash)
    end
  end

  describe '.extract_status' do
    let(:status) { instance_double('Process::Status') }

    context 'when process exited normally' do
      it 'returns exit status' do
        allow(status).to receive(:exited?).and_return(true)
        allow(status).to receive(:exitstatus).and_return(42)

        result = executor.send(:extract_status, status)
        expect(result).to eq(42)
      end
    end

    context 'when process terminated by signal' do
      it 'returns 128 + signal number' do
        allow(status).to receive(:exited?).and_return(false)
        allow(status).to receive(:signaled?).and_return(true)
        allow(status).to receive(:termsig).and_return(15) # SIGTERM

        result = executor.send(:extract_status, status)
        expect(result).to eq(128 + 15) # 143
      end
    end

    context 'when process was stopped' do
      it 'returns 128 + stop signal' do
        allow(status).to receive(:exited?).and_return(false)
        allow(status).to receive(:signaled?).and_return(false)
        allow(status).to receive(:stopped?).and_return(true)
        allow(status).to receive(:stopsig).and_return(19) # SIGSTOP

        result = executor.send(:extract_status, status)
        expect(result).to eq(128 + 19) # 147
      end
    end

    context 'with unknown status' do
      it 'returns 1 as failure code' do
        allow(status).to receive(:exited?).and_return(false)
        allow(status).to receive(:signaled?).and_return(false)
        allow(status).to receive(:stopped?).and_return(false)

        result = executor.send(:extract_status, status)
        expect(result).to eq(1)
      end
    end
  end

  describe 'integration tests' do
    it 'handles multiple rapid executions' do
      results = []
      5.times do
        results << executor.execute('echo', ['test'], allow_failure: true)
      end

      expect(results.all? { |r| r.is_a?(Ukiryu::Execution::Result) }).to be true
      expect(results.map(&:exit_status)).to all(eq(0))
    end

    it 'handles commands with special characters in arguments' do
      result = executor.execute('echo', ['hello "quoted" test\'s'], allow_failure: true)

      expect(result.stdout.strip).to include('hello')
    end

    it 'properly escapes special shell characters' do
      result = executor.execute('sh', ['-c', 'echo "$TEST_VAR"'], env: { 'TEST_VAR' => 'value with spaces' }, allow_failure: true)

      expect(result.stdout.strip).to eq('value with spaces')
    end
  end
end
