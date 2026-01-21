# frozen_string_literal: true

require "open3"
require "timeout"

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
      # @return [Result] execution result with composed OOP classes
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

        started_at = Time.now
        begin
          result = execute_with_timeout(command, env, timeout, cwd)
        rescue Timeout::Error
          finished_at = Time.now
          raise TimeoutError, "Command timed out after #{timeout} seconds: #{executable}"
        end
        finished_at = Time.now

        # Create OOP result components
        command_info = CommandInfo.new(
          executable: executable,
          arguments: args,
          full_command: command,
          shell: shell_name
        )

        output = Output.new(
          stdout: result[:stdout],
          stderr: result[:stderr],
          exit_status: result[:status]
        )

        metadata = ExecutionMetadata.new(
          started_at: started_at,
          finished_at: finished_at,
          timeout: timeout
        )

        # Check exit status
        if result[:status] != 0 && !options[:allow_failure]
          raise ExecutionError, format_error(executable, command, result)
        end

        Result.new(
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
        exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]

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

    # Execution command information
    #
    # Encapsulates details about the executed command
    class CommandInfo
      attr_reader :executable, :arguments, :full_command, :shell

      def initialize(executable:, arguments:, full_command:, shell: nil)
        @executable = executable
        @arguments = arguments
        @full_command = full_command
        @shell = shell
      end

      # Get the executable name only
      #
      # @return [String] executable name
      def executable_name
        File.basename(@executable)
      end

      # Get argument count
      #
      # @return [Integer] number of arguments
      def argument_count
        @arguments.count
      end

      # String representation
      #
      # @return [String] command string
      def to_s
        @full_command
      end

      # Inspect
      #
      # @return [String] inspection string
      def inspect
        "#<Ukiryu::Executor::CommandInfo exe=#{executable_name.inspect} args=#{argument_count}>"
      end

      # Convert to hash
      #
      # @return [Hash] command info as hash
      def to_h
        {
          executable: @executable,
          executable_name: executable_name,
          arguments: @arguments,
          full_command: @full_command,
          shell: @shell
        }
      end
    end

    # Captured output from command execution
    #
    # Provides typed access to stdout and stderr with parsing utilities
    class Output
      attr_reader :raw_stdout, :raw_stderr, :exit_status

      def initialize(stdout:, stderr:, exit_status:)
        @raw_stdout = stdout
        @raw_stderr = stderr
        @exit_status = exit_status
      end

      # Get stdout as a string (stripped)
      #
      # @return [String] stripped stdout
      def stdout
        @raw_stdout.strip
      end

      # Get stderr as a string (stripped)
      #
      # @return [String] stripped stderr
      def stderr
        @raw_stderr.strip
      end

      # Get stdout lines as an array
      #
      # @return [Array<String>] stdout split by lines
      def stdout_lines
        @raw_stdout.split("\n")
      end

      # Get stderr lines as an array
      #
      # @return [Array<String>] stderr split by lines
      def stderr_lines
        @raw_stderr.split("\n")
      end

      # Check if stdout contains a pattern
      #
      # @param pattern [String, Regexp] pattern to search for
      # @return [Boolean] true if pattern is found
      def stdout_contains?(pattern)
        if pattern.is_a?(Regexp)
          @raw_stdout.match?(pattern)
        else
          @raw_stdout.include?(pattern.to_s)
        end
      end

      # Check if stderr contains a pattern
      #
      # @param pattern [String, Regexp] pattern to search for
      # @return [Boolean] true if pattern is found
      def stderr_contains?(pattern)
        if pattern.is_a?(Regexp)
          @raw_stderr.match?(pattern)
        else
          @raw_stderr.include?(pattern.to_s)
        end
      end

      # Check if stdout is empty
      #
      # @return [Boolean] true if stdout is empty
      def stdout_empty?
        @raw_stdout.strip.empty?
      end

      # Check if stderr is empty
      #
      # @return [Boolean] true if stderr is empty
      def stderr_empty?
        @raw_stderr.strip.empty?
      end

      # Get stdout length
      #
      # @return [Integer] byte length of stdout
      def stdout_length
        @raw_stdout.length
      end

      # Get stderr length
      #
      # @return [Integer] byte length of stderr
      def stderr_length
        @raw_stderr.length
      end

      # Check if command succeeded
      #
      # @return [Boolean] true if exit status is 0
      def success?
        @exit_status == 0
      end

      # Check if command failed
      #
      # @return [Boolean] true if exit status is non-zero
      def failure?
        @exit_status != 0
      end

      # Convert to hash
      #
      # @return [Hash] output as hash
      def to_h
        {
          stdout: @raw_stdout,
          stderr: @raw_stderr,
          exit_status: @exit_status,
          success: success?,
          stdout_lines: stdout_lines,
          stderr_lines: stderr_lines
        }
      end

      # String representation
      #
      # @return [String] summary string
      def to_s
        if success?
          "Success (exit: #{@exit_status}, stdout: #{stdout_length} bytes, stderr: #{stderr_length} bytes)"
        else
          "Failed (exit: #{@exit_status}, stdout: #{stdout_length} bytes, stderr: #{stderr_length} bytes)"
        end
      end

      # Inspect
      #
      # @return [String] inspection string
      def inspect
        "#<Ukiryu::Executor::Output exit=#{@exit_status} success=#{success?}>"
      end
    end

    # Execution metadata
    #
    # Provides timing and execution environment information
    class ExecutionMetadata
      attr_reader :started_at, :finished_at, :duration, :timeout

      def initialize(started_at:, finished_at:, timeout: nil)
        @started_at = started_at
        @finished_at = finished_at
        @timeout = timeout
        @duration = calculate_duration
      end

      # Calculate duration from start and finish times
      #
      # @return [Float, nil] duration in seconds
      def calculate_duration
        return nil unless @started_at && @finished_at

        @finished_at - @started_at
      end

      # Get execution duration in seconds
      #
      # @return [Float, nil] duration in seconds
      def duration_seconds
        @duration
      end

      # Get execution duration in milliseconds
      #
      # @return [Float, nil] duration in milliseconds
      def duration_milliseconds
        @duration ? @duration * 1000 : nil
      end

      # Check if execution timed out
      #
      # @return [Boolean] true if timeout was set and exceeded
      def timed_out?
        return false unless @timeout && @duration

        @duration > @timeout
      end

      # Format duration for display
      #
      # @return [String] formatted duration
      def formatted_duration
        return "N/A" unless @duration

        if @duration < 1
          "#{(@duration * 1000).round(2)}ms"
        elsif @duration < 60
          "#{@duration.round(3)}s"
        else
          minutes = @duration / 60
          seconds = @duration % 60
          "#{minutes.to_i}m#{seconds.round(1)}s"
        end
      end

      # Convert to hash
      #
      # @return [Hash] metadata as hash
      def to_h
        {
          started_at: @started_at,
          finished_at: @finished_at,
          duration: @duration,
          duration_seconds: @duration,
          duration_milliseconds: duration_milliseconds,
          timeout: @timeout,
          timed_out: timed_out?
        }
      end

      # String representation
      #
      # @return [String] formatted string
      def to_s
        "duration: #{formatted_duration}"
      end

      # Inspect
      #
      # @return [String] inspection string
      def inspect
        "#<Ukiryu::Executor::ExecutionMetadata duration=#{formatted_duration}>"
      end
    end

    # Result class for command execution
    #
    # Provides a rich, object-oriented interface to command execution results.
    # Composes CommandInfo, Output, and ExecutionMetadata for a fully OOP design.
    class Result
      attr_reader :command_info, :output, :metadata

      # Initialize a new result
      #
      # @param command_info [CommandInfo] the command execution info
      # @param output [Output] the captured output
      # @param metadata [ExecutionMetadata] execution metadata
      def initialize(command_info:, output:, metadata:)
        @command_info = command_info
        @output = output
        @metadata = metadata
      end

      # Get the full command string
      #
      # @return [String] executed command
      def command
        @command_info.full_command
      end

      # Get the executable
      #
      # @return [String] executable path
      def executable
        @command_info.executable
      end

      # Get the executable name only
      #
      # @return [String] executable name
      def executable_name
        @command_info.executable_name
      end

      # Get raw stdout
      #
      # @return [String] raw stdout
      def stdout
        @output.raw_stdout
      end

      # Get raw stderr
      #
      # @return [String] raw stderr
      def stderr
        @output.raw_stderr
      end

      # Get exit status code
      #
      # @return [Integer] exit status
      def status
        @output.exit_status
      end
      alias exit_code status

      # Get the exit code (alias for status)
      #
      # @return [Integer] exit status
      def exit_status
        @output.exit_status
      end

      # Get start time
      #
      # @return [Time] when command started
      def started_at
        @metadata.started_at
      end

      # Get finish time
      #
      # @return [Time] when command finished
      def finished_at
        @metadata.finished_at
      end

      # Get execution duration
      #
      # @return [Float, nil] duration in seconds
      def duration
        @metadata.duration
      end

      # Get execution duration (alias)
      #
      # @return [Float, nil] duration in seconds
      def execution_time
        @metadata.duration_seconds
      end

      # Check if the command succeeded
      #
      # @return [Boolean]
      def success?
        @output.success?
      end

      # Check if the command failed
      #
      # @return [Boolean]
      def failure?
        @output.failure?
      end

      # Get stdout as a stripped string
      #
      # @return [String] stripped stdout
      def output
        @output.stdout
      end

      # Get stderr as a stripped string
      #
      # @return [String] stripped stderr
      def error_output
        @output.stderr
      end

      # Get stdout lines
      #
      # @return [Array<String>] stdout split by lines
      def stdout_lines
        @output.stdout_lines
      end

      # Get stderr lines
      #
      # @return [Array<String>] stderr split by lines
      def stderr_lines
        @output.stderr_lines
      end

      # Check if stdout contains a pattern
      #
      # @param pattern [String, Regexp] pattern to search for
      # @return [Boolean] true if pattern is found
      def stdout_contains?(pattern)
        @output.stdout_contains?(pattern)
      end

      # Check if stderr contains a pattern
      #
      # @param pattern [String, Regexp] pattern to search for
      # @return [Boolean] true if pattern is found
      def stderr_contains?(pattern)
        @output.stderr_contains?(pattern)
      end

      # Get a hash representation of the result
      #
      # @return [Hash] result data as a hash
      def to_h
        {
          command: @command_info.to_h,
          output: @output.to_h,
          metadata: @metadata.to_h,
          success: success?,
          status: status
        }
      end

      # Get a JSON representation of the result
      #
      # @return [String] result data as JSON
      def to_json(*args)
        require 'json'
        to_h.to_json(*args)
      end

      # String representation of the result
      #
      # @return [String] summary of the result
      def to_s
        if success?
          "Success (#{@command_info.executable_name}, status: #{status}, duration: #{@metadata.formatted_duration})"
        else
          "Failed (#{@command_info.executable_name}, status: #{status}, duration: #{@metadata.formatted_duration})"
        end
      end

      # Inspect the result (for debugging)
      #
      # @return [String] detailed inspection string
      def inspect
        "#<Ukiryu::Executor::Result exe=#{@command_info.executable_name.inspect} status=#{status} duration=#{@metadata.formatted_duration}>"
      end
    end
  end
end
