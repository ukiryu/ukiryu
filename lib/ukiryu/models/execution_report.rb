# frozen_string_literal: true

module Ukiryu
  module Models
    # Execution report containing metrics and timing information
    #
    # Provides detailed metrics about the execution process including:
    # - Stage timings (tool resolution, command building, execution)
    # - Memory usage
    # - Run environment information
    class ExecutionReport < Lutaml::Model::Serializable
      attribute :tool_resolution, StageMetrics
      attribute :command_building, StageMetrics
      attribute :execution, StageMetrics
      attribute :response_building, StageMetrics
      attribute :total_duration, :float, default: 0.0
      attribute :formatted_total_duration, :string, default: ''
      attribute :run_environment, RunEnvironment
      attribute :timestamp, :string, default: ''

      key_value do
        map 'tool_resolution', to: :tool_resolution
        map 'command_building', to: :command_building
        map 'execution', to: :execution
        map 'response_building', to: :response_building
        map 'total_duration', to: :total_duration
        map 'formatted_total_duration', to: :formatted_total_duration
        map 'run_environment', to: :run_environment
        map 'timestamp', to: :timestamp
      end

      # Calculate total duration from all stages
      def calculate_total
        stages = [tool_resolution, command_building, execution, response_building]
        total = stages.compact.map(&:duration).sum
        @total_duration = total
        @formatted_total_duration = format_duration(total)
      end

      # Get all stages in order
      #
      # @return [Array<StageMetrics>] all stages
      def all_stages
        [tool_resolution, command_building, execution, response_building].compact
      end

      private

      def format_duration(seconds)
        return '0ms' if seconds.zero?
        return "#{(seconds * 1000).round(2)}ms" if seconds < 1

        "#{seconds.round(2)}s"
      end
    end
  end
end
