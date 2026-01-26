# frozen_string_literal: true

require 'open3'
require 'timeout'
require_relative 'execution'
require_relative 'shell'

module Ukiryu
  # Command execution with platform-specific methods
  #
  # Handles execution of external commands with:
  # - Shell-specific command line building
  # - Environment variable management
  # - Timeout handling
  # - Error detection and reporting
  module Executor
    class << self
      # Execute a command with the the given options
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the command arguments
      # @param options [Hash] execution options
      # @option options [Integer] :timeout maximum execution time in seconds
      # @option options [Hash] :env environment variables
      # @option options [String] :cwd working directory
      # @option options [Symbol] :shell shell to use (default: auto-detect)
      # @option options [String, IO] :stdin stdin input data (string or IO object)
      # @option options [String] :tool_name tool name for exit code lookups
      # @option options [String] :command_name command name for exit code lookups
      # @return [Execution::Result] execution result with composed OOP classes
      # @raise [TimeoutError] if command times out
      # @raise [ExecutionError] if command fails
      def execute(executable, args = [], options = {})
        shell_name = options[:shell] || Shell.detect
        shell_class = Shell.class_for(shell_name)

        # Format the command line
        command = build_command(executable, args, shell_class)

        # Prepare environment
        env = prepare_environment(options[:env] || {}, shell_class)

        # Execute with timeout
        timeout = options[:timeout] || 90
        cwd = options[:cwd]
        stdin = options[:stdin]

        # Suppress thread warnings from Open3 (cosmetic IOError from stream closure)
        # Open3's internal threads may raise IOError when streams close early
        original_setting = Thread.report_on_exception
        Thread.report_on_exception = false

        started_at = Time.now
        begin
          result = if stdin
                     execute_with_stdin(command, env, timeout, cwd, stdin)
                   else
                     execute_with_timeout(command, env, timeout, cwd)
                   end
        rescue Timeout::Error
          Time.now
          raise TimeoutError, "Command timed out after #{timeout} seconds: #{executable}"
        ensure
          Thread.report_on_exception = original_setting
        end
        finished_at = Time.now

        # Create OOP result components using Execution namespace
        command_info = Execution::CommandInfo.new(
          executable: executable,
          arguments: args,
          full_command: command,
          shell: shell_name,
          tool_name: options[:tool_name],
          command_name: options[:command_name]
        )

        output = Execution::Output.new(
          stdout: result[:stdout],
          stderr: result[:stderr],
          exit_status: result[:status]
        )

        metadata = Execution::ExecutionMetadata.new(
          started_at: started_at,
          finished_at: finished_at,
          timeout: timeout
        )

        # Check exit status
        if result[:status] != 0 && !options[:allow_failure]
          raise ExecutionError,
                format_error(executable, command, result)
        end

        Execution::Result.new(
          command_info: command_info,
          output: output,
          metadata: metadata
        )
      end

      # Find an executable in the system PATH
      #
      # @param command [String] the command or executable name
      # @param options [Hash] search options
      # @option options [Array<String>] :additional_paths additional search paths
      # @return [String, nil] the full path to the executable, or nil if not found
      def find_executable(command, options = {})
        # Try with PATHEXT extensions (Windows executables)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']

        search_paths = Platform.executable_search_paths
        search_paths.concat(options[:additional_paths]) if options[:additional_paths]
        search_paths.uniq!

        search_paths.each do |dir|
          exts.each do |ext|
            exe = File.join(dir, "#{command}#{ext}")
            return exe if File.executable?(exe) && !File.directory?(exe)
          end
        end

        nil
      end

      # Build a command line for the given shell
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @param shell_class [Class] the shell implementation class
      # @return [String] the complete command line
      def build_command(executable, args, shell_class)
        shell_instance = shell_class.new

        # Format executable path if needed
        exe = shell_instance.format_path(executable)

        # Join executable and arguments
        shell_instance.join(exe, *args)
      end

      private

      # Execute command with timeout in current directory
      #
      # @param command [String] the command to execute
      # @param env [Hash] environment variables
      # @param timeout [Integer] timeout in seconds
      # @return [Hash] execution result
      def execute_with_timeout(command, env, timeout)
        Timeout.timeout(timeout) do
          stdout, stderr, status = Open3.capture3(env, command)
          {
            status: status.exitstatus || 0,
            stdout: stdout,
            stderr: stderr
          }
        end
      end

      # Execute command with timeout in specific directory
      #
      # @param command [String] the command to execute
      # @param env [Hash] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @return [Hash] execution result
      def execute_with_timeout(command, env, timeout, cwd = nil)
        Timeout.timeout(timeout) do
          if cwd
            Dir.chdir(cwd) do
              stdout, stderr, status = Open3.capture3(env, command)
              {
                status: extract_status(status),
                stdout: stdout,
                stderr: stderr
              }
            end
          else
            stdout, stderr, status = Open3.capture3(env, command)
            {
              status: extract_status(status),
              stdout: stdout,
              stderr: stderr
            }
          end
        end
      end

      # Execute command with stdin input
      #
      # @param command [String] the command to execute
      # @param env [Hash] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @param stdin_data [String, IO] stdin input data
      # @return [Hash] execution result
      def execute_with_stdin(command, env, timeout, cwd, stdin_data)
        Timeout.timeout(timeout) do
          execution = lambda do
            Open3.popen3(env, command) do |stdin, stdout, stderr, wait_thr|
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
                status: extract_status(status),
                stdout: out,
                stderr: err
              }
            end
          end

          if cwd
            Dir.chdir(cwd) do
              execution.call
            end
          else
            execution.call
          end
        end
      end

      # Extract exit status from Process::Status
      #
      # @param status [Process::Status] the process status
      # @return [Integer] exit status (128 + signal if terminated by signal)
      def extract_status(status)
        if status.exited?
          status.exitstatus
        elsif status.signaled?
          # Process terminated by signal - return 128 + signal number
          # This matches how shells report terminated processes
          128 + status.termsig
        elsif status.stopped?
          # Process was stopped - return 128 + stop signal
          128 + status.stopsig
        else
          # Unknown status - return failure code
          1
        end
      end

      # Prepare environment variables
      #
      # @param user_env [Hash] user-specified environment variables
      # @param shell_class [Class] the shell implementation class
      # @return [Hash] merged environment variables
      def prepare_environment(user_env, shell_class)
        shell_instance = shell_class.new

        # Start with current environment
        env = ENV.to_h.dup

        # Add user-specified variables
        user_env.each do |key, value|
          env[key] = value
        end

        # Add shell-specific headless environment
        headless = shell_instance.headless_environment

        # For headless mode, explicitly remove DISPLAY
        # If user_env explicitly didn't set DISPLAY, respect that (caller wants it removed)
        # Otherwise, check if headless environment specifies DISPLAY
        env.delete('DISPLAY') unless headless.key?('DISPLAY')

        env.merge!(headless)

        env
      end

      # Format an execution error message
      #
      # @param executable [String] the executable name
      # @param command [String] the full command
      # @param result [Hash] the execution result
      # @return [String] formatted error message
      def format_error(executable, command, result)
        <<~ERROR.chomp
          Command failed: #{executable}

          Command: #{command}
          Exit status: #{result[:status]}

          STDOUT:
          #{result[:stdout].strip}

          STDERR:
          #{result[:stderr].strip}
        ERROR
      end
    end
  end
end
