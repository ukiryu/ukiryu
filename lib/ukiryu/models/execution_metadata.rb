# frozen_string_literal: true

module Ukiryu
  module Models
    # Execution metadata
    #
    # Contains timing and duration information about command execution.
    class ExecutionMetadata < Lutaml::Model::Serializable
      attribute :started_at, :string
      attribute :finished_at, :string
      attribute :duration_seconds, :float
      attribute :formatted_duration, :string

      key_value do
        map 'started_at', to: :started_at
        map 'finished_at', to: :finished_at
        map 'duration_seconds', to: :duration_seconds
        map 'formatted_duration', to: :formatted_duration
      end
    end
  end
end
