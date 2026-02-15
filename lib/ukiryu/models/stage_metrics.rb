# frozen_string_literal: true

module Ukiryu
  module Models
    # Metrics for a single stage of execution
    class StageMetrics < Lutaml::Model::Serializable
      attribute :name, :string, default: ''
      attribute :duration, :float, default: 0.0
      attribute :formatted_duration, :string, default: ''
      attribute :memory_before, :integer, default: 0
      attribute :memory_after, :integer, default: 0
      attribute :memory_delta, :integer, default: 0
      attribute :success, :boolean, default: true
      attribute :error, :string, default: ''

      key_value do
        map 'name', to: :name
        map 'duration', to: :duration
        map 'formatted_duration', to: :formatted_duration
        map 'memory_before', to: :memory_before
        map 'memory_after', to: :memory_after
        map 'memory_delta', to: :memory_delta
        map 'success', to: :success
        map 'error', to: :error
      end

      # Record the end of a stage
      def finish!(success: true, error: nil)
        @duration = Time.now - @start_time if @start_time
        @formatted_duration = format_duration(@duration)
        @success = success
        @error = error if error

        # Record memory after
        @memory_after = get_memory_usage
        @memory_delta = @memory_after - @memory_before
      end

      # Start recording this stage
      def start!
        @start_time = Time.now
        @memory_before = get_memory_usage
        self
      end

      private

      def get_memory_usage
        # Get RSS memory usage in KB
        `ps -o rss= -p #{Process.pid}`.to_i
      rescue StandardError
        0
      end

      def format_duration(seconds)
        return '0ms' if seconds.nil? || seconds.zero?
        return "#{(seconds * 1000).round(2)}ms" if seconds < 1

        "#{seconds.round(2)}s"
      end
    end
  end
end
