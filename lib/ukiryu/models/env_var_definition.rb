# frozen_string_literal: true

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
      attribute :platforms, :string, collection: true, initialize_empty: true
      attribute :description, :string

      key_value do
        map 'name', to: :name
        map 'value', to: :value
        map 'from', to: :from
        map 'platforms', to: :platforms
        map 'description', to: :description
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
