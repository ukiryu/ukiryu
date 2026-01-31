# frozen_string_literal: true

require 'open3'
require 'timeout'

module Ukiryu
  module Shell
    # Base class for Unix-like shells (bash, zsh, fish, sh)
    #
    # Unix shells use:
    # - Single quotes for literal strings
    # - $VAR for environment variables
    # - shell -c 'command' for execution
    class UnixBase < Base
      PLATFORM = :unix
      # Get the shell command name to search for
      #
      # @return [String] the shell command name (e.g., 'bash', 'zsh')
      def shell_command
        raise NotImplementedError, "#{self.class} must implement #shell_command"
      end

      # Get the shell executable path (found dynamically)
      #
      # @return [String] the shell executable path
      # @raise [RuntimeError] if shell is not found on the system
      def shell_executable
        @shell_executable ||= find_shell_executable
      end

      # Execute a command using this shell
      #
      # Uses the shell's -c flag to execute the command string.
      # This ensures the command is interpreted by the correct shell (bash, zsh, etc.)
      # rather than /bin/sh (which might be dash on some systems).
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command(executable, args, env, timeout, cwd = nil)
        # Build command string using this shell's quoting rules
        command_string = join(executable, *args)

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using the shell's -c flag
        # This ensures the command is interpreted by THIS shell, not /bin/sh
        Timeout.timeout(timeout) do
          execution = lambda do
            stdout, stderr, status = Open3.capture3(env_hash, shell_executable, '-c', command_string)
            {
              status: Ukiryu::Executor.extract_status(status),
              stdout: stdout,
              stderr: stderr
            }
          end

          if cwd
            Dir.chdir(cwd) { execution.call }
          else
            execution.call
          end
        end
      rescue Timeout::Error, Timeout::ExitException
        # Re-raise with context
        raise Timeout::Error, "Command timed out after #{timeout}s: #{executable}"
      end

      # Execute a command with stdin input using this shell
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @param stdin_data [String, IO] stdin input data
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command_with_stdin(executable, args, env, timeout, cwd, stdin_data)
        # Build command string using this shell's quoting rules
        command_string = join(executable, *args)

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using the shell's -c flag
        Timeout.timeout(timeout) do
          execution = lambda do
            Open3.popen3(env_hash, shell_executable, '-c', command_string) do |stdin, stdout, stderr, wait_thr|
              # Write stdin data
              begin
                if stdin_data.is_a?(IO)
                  IO.copy_stream(stdin_data, stdin)
                elsif stdin_data.is_a?(String)
                  stdin.write(stdin_data)
                end
              rescue Errno::EPIPE
                # Process closed stdin early (e.g., 'head' command)
              ensure
                stdin.close
              end

              # Read output
              out = stdout.read
              err = stderr.read

              # Wait for process to complete
              status = wait_thr.value

              {
                status: Ukiryu::Executor.extract_status(status),
                stdout: out,
                stderr: err
              }
            end
          end

          if cwd
            Dir.chdir(cwd) { execution.call }
          else
            execution.call
          end
        end
      rescue Timeout::Error, Timeout::ExitException
        # Re-raise with context
        raise Timeout::Error, "Command timed out after #{timeout}s: #{executable}"
      end

      private

      # Find the shell executable in the system PATH
      #
      # @return [String] the shell executable path
      # @raise [RuntimeError] if shell is not found
      def find_shell_executable
        command = shell_command
        path = Ukiryu::Executor.find_executable(command)

        raise "Shell '#{command}' not found in system PATH" unless path

        path
      end
    end
  end
end
