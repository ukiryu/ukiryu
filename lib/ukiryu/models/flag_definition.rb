# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Flag definition for a command
    #
    # Represents a boolean flag (present or absent)
    #
    # @example
    #   flag = FlagDefinition.new(
    #     name: 'verbose',
    #     cli: '-v',
    #     default: false,
    #     description: 'Enable verbose output'
    #   )
    class FlagDefinition < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :cli, :string
      attribute :default, :boolean, default: false
      attribute :description, :string
      attribute :platforms, :string, collection: true, default: []

      yaml do
        map_element 'name', to: :name
        map_element 'cli', to: :cli
        map_element 'default', to: :default
        map_element 'description', to: :description
        map_element 'platforms', to: :platforms
      end

      # Get the effective default value
      #
      # @return [Boolean] the default value
      def default_value
        default || false
      end

      # Check if flag applies to a platform
      #
      # @param platform [Symbol] the platform
      # @return [Boolean] true if applies
      def applies_to?(platform)
        return true if platforms.nil? || platforms.empty?

        cached_platforms_sym.include?(platform.to_sym)
      end

      # Get name as symbol (cached for performance)
      #
      # @return [Symbol] the name as symbol
      def name_sym
        @name_sym ||= name.to_sym
      end

      private

      # Get platforms as cached symbol array
      #
      # @api private
      def cached_platforms_sym
        @cached_platforms_sym ||= platforms&.map(&:to_sym) || []
      end
    end
  end
end
