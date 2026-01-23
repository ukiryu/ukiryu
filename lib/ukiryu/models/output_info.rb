# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Command output information
    #
    # Contains the standard output and error output from command execution.
    class OutputInfo < Lutaml::Model::Serializable
      attribute :stdout, :string, default: ''
      attribute :stderr, :string, default: ''

      yaml do
        map_element 'stdout', to: :stdout
        map_element 'stderr', to: :stderr
      end

      json do
        map 'stdout', to: :stdout
        map 'stderr', to: :stderr
      end
    end
  end
end
