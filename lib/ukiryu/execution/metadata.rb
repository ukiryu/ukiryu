# frozen_string_literal: true

module Ukiryu
  module Execution
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
        return 'N/A' unless @duration

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
        "#<Ukiryu::Execution::ExecutionMetadata duration=#{formatted_duration}>"
      end
    end
  end
end
