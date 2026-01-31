# frozen_string_literal: true

module Ukiryu
  module Execution
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
        @raw_stdout.split(/\r?\n/)
      end

      # Get stderr lines as an array
      #
      # @return [Array<String>] stderr split by lines
      def stderr_lines
        @raw_stderr.split(/\r?\n/)
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
        @exit_status.zero?
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
        "#<Ukiryu::Execution::Output exit=#{@exit_status} success=#{success?}>"
      end
    end
  end
end
