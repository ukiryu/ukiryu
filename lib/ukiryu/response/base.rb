# frozen_string_literal: true

module Ukiryu
  module Response
    # Abstract base class for all response classes
    #
    # This class wraps the raw Executor::Result object and provides
    # a structured interface for accessing command execution results.
    #
    # @abstract
    class Base
      # Create a new response
      #
      # @param result [Executor::Result] the raw execution result
      def initialize(result)
        @result = result
      end

      # Check if the command was successful
      #
      # @return [Boolean] true if exit code was 0
      def success?
        @result.status.zero?
      end

      # Get the exit code
      #
      # @return [Integer] the exit code
      def exit_code
        @result.status
      end

      # Get the exit code meaning (symbol)
      #
      # @return [String, nil] the exit code meaning (e.g., "merge_conflict") or nil if not defined
      def exit_code_meaning
        tool_name = @result.command_info.tool_name
        command_name = @result.command_info.command_name
        return nil unless tool_name && command_name

        # Look up the tool by name
        require_relative '../tool'
        tool = Tool.find_by(tool_name.to_sym)
        return nil unless tool

        # Get exit codes from the tool's profile
        profile = tool.profile
        return nil unless profile

        command_profile = profile.compatible_profile
        return nil unless command_profile

        # First, try to get exit codes from the specific command
        command = command_profile.command(command_name.to_s)
        exit_codes = command&.exit_codes

        # Fall back to profile-level exit codes if command doesn't define its own
        exit_codes ||= command_profile.exit_codes
        return nil unless exit_codes

        exit_codes.meaning(@result.status)
      end

      # Get the standard output
      #
      # @return [String] the stdout content
      def stdout
        @result.output
      end

      # Get the standard error
      #
      # @return [String] the stderr content
      def stderr
        @result.error_output
      end

      # Get stdout as lines
      #
      # @return [Array<String>] the stdout split into lines
      def stdout_lines
        @result.stdout_lines
      end

      # Get stderr as lines
      #
      # @return [Array<String>] the stderr split into lines
      def stderr_lines
        @result.stderr_lines
      end

      # Get the command that was executed
      #
      # @return [String] the full command string
      def command
        @result.command_info.full_command
      end

      # Get the executable path
      #
      # @return [String] the executable that was run
      def executable
        @result.command_info.executable
      end

      # Get the command arguments
      #
      # @return [Array<String>] the arguments passed to the command
      def arguments
        @result.command_info.arguments
      end

      # Get the shell type used
      #
      # @return [Symbol] the shell type
      def shell
        @result.command_info.shell
      end

      # Get the execution duration
      #
      # @return [Float] duration in seconds
      def duration
        @result.metadata.duration
      end

      # Get the formatted duration string
      #
      # @return [String] human-readable duration (e.g., "1.2s", "450ms")
      def formatted_duration
        @result.metadata.formatted_duration
      end

      # Get the start time
      #
      # @return [Time] when the command started
      def started_at
        @result.metadata.started_at
      end

      # Get the end time
      #
      # @return [Time] when the command finished
      def finished_at
        @result.metadata.finished_at
      end

      # Check if the command timed out
      #
      # @return [Boolean] true if the command exceeded its timeout
      def timed_out?
        @result.timeout_exceeded?
      end

      # Get the raw result object
      #
      # @return [Executor::Result] the raw execution result
      def raw_result
        @result
      end

      # Convert to hash representation
      #
      # @return [Hash] hash representation of the response
      def to_h
        hash = {
          success: success?,
          exit_code: exit_code,
          stdout: stdout,
          stderr: stderr,
          command: command,
          executable: executable,
          arguments: arguments,
          shell: shell,
          duration: duration,
          started_at: started_at.iso8601,
          finished_at: finished_at.iso8601
        }

        # Add exit code meaning if available
        meaning = exit_code_meaning
        hash[:exit_code_meaning] = meaning if meaning

        hash
      end
      alias to_hash to_h

      # String representation
      #
      # @return [String] summary of the response
      def to_s
        if success?
          "Success (exit #{exit_code}#{format_meaning}, #{formatted_duration})"
        else
          "Failed (exit #{exit_code}#{format_meaning}, #{formatted_duration})"
        end
      end

      # Format exit code meaning
      #
      # @return [String] formatted meaning (e.g., ": merge_conflict")
      def format_meaning
        meaning = exit_code_meaning
        return '' unless meaning

        ": #{meaning}"
      end

      # Inspect representation
      #
      # @return [String] detailed inspection string
      def inspect
        "#<#{self.class.name} success=#{success?} exit_code=#{exit_code} duration=#{formatted_duration}>"
      end
    end
  end
end
