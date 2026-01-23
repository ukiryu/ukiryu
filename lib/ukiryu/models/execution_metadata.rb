# frozen_string_literal: true

require 'lutaml/model'

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

      yaml do
        map_element 'started_at', to: :started_at
        map_element 'finished_at', to: :finished_at
        map_element 'duration_seconds', to: :duration_seconds
        map_element 'formatted_duration', to: :formatted_duration
      end

      json do
        map 'started_at', to: :started_at
        map 'finished_at', to: :finished_at
        map 'duration_seconds', to: :duration_seconds
        map 'formatted_duration', to: :formatted_duration
      end
    end
  end
end
