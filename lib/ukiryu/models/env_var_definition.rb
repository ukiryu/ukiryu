# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Environment variable definition for a command
    #
    # @example
    #   env_var = EnvVarDefinition.new(
    #     name: 'DISPLAY',
    #     value: '',
    #     platforms: [:linux, :macos]
    #   )
    class EnvVarDefinition < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :value, :string
      attribute :from, :string
      attribute :platforms, :string, collection: true, default: []
      attribute :description, :string

      yaml do
        map_element 'name', to: :name
        map_element 'value', to: :value
        map_element 'from', to: :from
        map_element 'platforms', to: :platforms
        map_element 'description', to: :description
      end

      # Get platforms as symbol array
      #
      # @return [Array<Symbol>] platforms as symbols
      def platforms_sym
        @platforms_sym ||= platforms&.map(&:to_sym) || []
      end
    end
  end
end
