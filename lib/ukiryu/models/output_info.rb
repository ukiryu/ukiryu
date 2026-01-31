# frozen_string_literal: true

module Ukiryu
  module Models
    # Command output information
    #
    # Contains the standard output and error output from command execution.
    class OutputInfo < Lutaml::Model::Serializable
      attribute :stdout, :string, default: ''
      attribute :stderr, :string, default: ''

      key_value do
        map 'stdout', to: :stdout
        map 'stderr', to: :stderr
      end
    end
  end
end
