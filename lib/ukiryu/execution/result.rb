# frozen_string_literal: true

module Ukiryu
  module Execution
    # Result class for command execution
    #
    # Provides a rich, object-oriented interface to command execution results.
    # Composes CommandInfo, Output, and ExecutionMetadata for a fully OOP design.
    class Result
      attr_reader :command_info, :output, :metadata

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
      # @return [String] summary string
      def to_s
        if success?
          "Success: #{command} (#{metadata.formatted_duration})"
        else
          "Failed: #{command} (exit: #{status}, #{metadata.formatted_duration})"
        end
      end

      # Inspect
      #
      # @return [String] inspection string
      def inspect
        "#<Ukiryu::Execution::Result #{self}>"
      end
    end
  end
end
