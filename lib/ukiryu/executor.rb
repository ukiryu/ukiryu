# frozen_string_literal: true

require 'open3'
require 'timeout'
require_relative 'errors'

module Ukiryu
  # Command execution with platform-specific methods
  #
  # Handles execution of external commands with:
  # - Shell-specific command line building
  # - Environment variable management
  # - Timeout handling
  # - Error detection and reporting
  module Executor
    # Autoload Execution module for Result classes
    autoload :Execution, 'ukiryu/execution'

    class << self
      # Execute a command with the given options
      #
      # The user MUST explicitly specify both:
      # - env: The Environment to use (inherited, derived, custom, or empty)
      # - shell: The Shell to interpret the command (bash, zsh, powershell, cmd, etc.)
      # - timeout: Maximum execution time in seconds
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the command arguments
      # @param options [Hash] execution options
      # @option options [Environment] :env REQUIRED - The environment to use
      # @option options [Class, Symbol] :shell REQUIRED - Shell class or shell name (:bash, :zsh, :powershell, :cmd)
      # @option options [Integer] :timeout REQUIRED - maximum execution time in seconds
      # @option options [String] :cwd working directory
      # @option options [String, IO] :stdin stdin input data (string or IO object)
      # @option options [String] :tool_name tool name for exit code lookups
      # @option options [String] :command_name command name for exit code lookups
      # @option options [Boolean] :allow_failure allow non-zero exit codes (default: false)
      # @return [Execution::Result] execution result with composed OOP classes
      # @raise [ArgumentError] if shell or timeout is not specified
      # @raise [TimeoutError] if command times out
      # @raise [ExecutionError] if command fails
      def execute(executable, args = [], options = {})
        # Get shell - must be explicitly specified
        shell_arg = options[:shell]
        raise ArgumentError, 'shell is required - specify :shell option (e.g., shell: :bash)' unless shell_arg

        # Get timeout - must be explicitly specified
        timeout = options[:timeout]
        raise ArgumentError, 'timeout is required - specify :timeout option (e.g., timeout: 90)' unless timeout

        # Convert shell to shell class
        shell_class = if shell_arg.is_a?(Class)
                        shell_arg
                      else
                        Ukiryu::Shell.class_for(shell_arg.to_sym)
                      end

        shell_instance = shell_class.new

        # Debug logging for Ruby 4.0 CI
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG Executor#execute] executable: #{executable.inspect}"
          warn "[UKIRYU DEBUG Executor#execute] args: #{args.inspect}"
          warn "[UKIRYU DEBUG Executor#execute] args.class: #{args.class}"
          warn "[UKIRYU DEBUG Executor#execute] shell_class: #{shell_class}"
        end

        # Prepare environment (requires Environment or Hash)
        env = prepare_environment(options[:env] || {}, shell_class)
        cwd = options[:cwd]
        stdin = options[:stdin]

        # Suppress thread warnings from Open3 (cosmetic IOError from stream closure)
        # Open3's internal threads may raise IOError when streams close early
        original_setting = Thread.report_on_exception
        Thread.report_on_exception = false

        started_at = Time.now
        begin
          result = if stdin
                     shell_instance.execute_command_with_stdin(executable, args, env, timeout, cwd, stdin)
                   else
                     shell_instance.execute_command(executable, args, env, timeout, cwd)
                   end
        rescue Timeout::Error
          Time.now
          raise Ukiryu::Errors::TimeoutError, "Command timed out after #{timeout} seconds: #{executable}"
        ensure
          Thread.report_on_exception = original_setting
        end
        finished_at = Time.now

        # Build command string for display (for error messages and debugging)
        command = shell_instance.join(executable, *args)

        # Create OOP result components using Execution namespace
        command_info = Execution::CommandInfo.new(
          executable: executable,
          arguments: args,
          full_command: command,
          shell: shell_instance.name,
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
          raise Ukiryu::Errors::ExecutionError,
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

      private

      # Execute command with timeout in current directory
      # Deprecated: Use the version that takes executable and args separately
      #
      # @param command [String] the command to execute
      # @param env [Hash] environment variables
      # @param timeout [Integer] timeout in seconds
      # @return [Hash] execution result
      def execute_with_timeout(command, env, timeout)
        # This method is kept for backward compatibility but should not be used
        # The main execute() method now calls execute_with_timeout(executable, args, ...)
        Timeout.timeout(timeout) do
          stdout, stderr, status = Open3.capture3(env, command)
          {
            status: status.exitstatus || 0,
            stdout: stdout,
            stderr: stderr
          }
        end
      rescue Timeout::Error, Timeout::ExitException
        # Re-raise to be caught by outer rescue
        raise
      end

      # Execute command with timeout in specific directory
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the command arguments
      # @param env [Hash] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @param shell_class [Class] the shell implementation class
      # @param use_array_form [Boolean] whether to use array form (true) or string form (false)
      # @return [Hash] execution result
      def execute_with_timeout(executable, args, env, timeout, cwd = nil, shell_class = nil, use_array_form = true)
        exec_start = Time.now
        Timeout.timeout(timeout) do
          if use_array_form
            # Use array form to avoid shell interpretation (Unix shells)
            # Open3.capture3 with array executes directly without /bin/sh -c
            cmd_array = [executable, *args]
            if cwd
              Dir.chdir(cwd) do
                stdout, stderr, status = Open3.capture3(env, *cmd_array)
                {
                  status: extract_status(status),
                  stdout: stdout,
                  stderr: stderr
                }
              end
            else
              stdout, stderr, status = Open3.capture3(env, *cmd_array)
              {
                status: extract_status(status),
                stdout: stdout,
                stderr: stderr
              }
            end
          else
            # Use string form for Windows shells (PowerShell/CMD require shell interpretation)
            command = shell_class ? shell_class.new.join(executable, *args) : executable
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
      rescue Timeout::Error, Timeout::ExitException
        elapsed = Time.now - exec_start
        warn "[UKIRYU DEBUG] Command timed out after #{elapsed.round(2)}s: #{executable}"
        # Re-raise to be caught by outer rescue
        raise
      end

      # Execute command with stdin input
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the command arguments
      # @param env [Hash] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @param stdin_data [String, IO] stdin input data
      # @param shell_class [Class] the shell implementation class
      # @param use_array_form [Boolean] whether to use array form (true) or string form (false)
      # @return [Hash] execution result
      def execute_with_stdin(executable, args, env, timeout, cwd, stdin_data, shell_class = nil, use_array_form = true)
        Timeout.timeout(timeout) do
          execution = lambda do
            if use_array_form
              # Use array form to avoid shell interpretation (Unix shells)
              cmd_array = [executable, *args]
              Open3.popen3(env, *cmd_array) do |stdin, stdout, stderr, wait_thr|
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
            else
              # Use string form for Windows shells (PowerShell/CMD require shell interpretation)
              command = shell_class ? shell_class.new.join(executable, *args) : executable
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
          end

          if cwd
            Dir.chdir(cwd) do
              execution.call
            end
          else
            execution.call
          end
        end
      rescue Timeout::Error, Timeout::ExitException
        # Re-raise to be caught by outer rescue
        raise
      end

      # Prepare environment variables
      #
      # Accepts either an Environment object or a Hash for backward compatibility.
      # Returns an Environment object with shell-specific modifications applied.
      # The Environment object is passed through to the Shell instance, which
      # converts to Hash only at the Open3 call site.
      #
      # @param user_env [Environment, Hash] user-specified environment variables
      # @param shell_class [Class] the shell implementation class
      # @return [Environment] merged environment variables
      def prepare_environment(user_env, shell_class)
        shell_instance = shell_class.new

        # Convert to Environment if needed (backward compatible with Hash)
        # Start with inherited ENV, then merge user's variables
        env = if user_env.is_a?(Environment)
                # Environment object: use as-is (already includes inherited ENV if created via from_env)
                user_env
              else
                # Hash: inherit from current ENV, then merge user's variables
                Ukiryu::Environment.from_env.merge(user_env.transform_values(&:to_s))
              end

        # Get shell-specific headless environment
        headless = shell_instance.headless_environment

        # Apply headless modifications to Environment
        # For headless mode, explicitly remove DISPLAY if not already set by user
        if headless.is_a?(Hash)
          # headless_environment returns Hash in current implementation
          # Apply modifications immutably
          env = if headless.key?('DISPLAY')
                  # Shell explicitly sets DISPLAY (possibly to empty string)
                  env.set('DISPLAY', headless['DISPLAY'])
                else
                  # Shell doesn't want DISPLAY at all - remove it
                  env.delete('DISPLAY')
                end

          # Apply other headless variables
          headless.each do |key, value|
            next if key == 'DISPLAY' # Already handled above

            env = env.set(key, value)
          end
        else
          # headless is empty or nil
          env = env.delete('DISPLAY')
        end

        env
      end

      # Format an execution error message
      #
      # @param executable [String] the executable name
      # @param command [String] the full command
      # @param result [Hash] the execution result
      # @return [String] formatted error message
      def format_error(executable, command, result)
        stdout = result[:stdout]&.strip || ''
        stderr = result[:stderr]&.strip || ''
        <<~ERROR.chomp
          Command failed: #{executable}

          Command: #{command}
          Exit status: #{result[:status]}

          STDOUT:
          #{stdout}

          STDERR:
          #{stderr}
        ERROR
      end
    end
  end
end
