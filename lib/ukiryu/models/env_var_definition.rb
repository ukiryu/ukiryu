# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Environment variable definition for a command
    #
    # @example
    #   env_var = EnvVarDefinition.new(
    #     name: 'DISPLAY',
    #     env_var: 'DISPLAY',
    #     value: '',
    #     platforms: [:linux, :macos]
    #   )
    class EnvVarDefinition < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :env_var, :string
      attribute :value, :string
      attribute :platforms, :string, collection: true, default: []

      yaml do
        map_element 'name', to: :name
        map_element 'env_var', to: :env_var
        map_element 'value', to: :value
        map_element 'platforms', to: :platforms
      end
    end
  end
end
