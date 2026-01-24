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
      attribute :cli_short, :string
      attribute :default, :boolean, default: false
      attribute :description, :string
      attribute :platforms, :string, collection: true, default: []
      attribute :position_constraint, :string
      attribute :position_after, :string
      attribute :conflicts_with, :string, collection: true, default: []

      yaml do
        map_element 'name', to: :name
        map_element 'cli', to: :cli
        map_element 'cli_short', to: :cli_short
        map_element 'default', to: :default
        map_element 'description', to: :description
        map_element 'platforms', to: :platforms
        map_element 'position_constraint', to: :position_constraint
        map_element 'position_after', to: :position_after
        map_element 'conflicts_with', to: :conflicts_with
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

      # Get position_constraint as symbol (cached)
      #
      # @return [Symbol, nil] the position constraint as symbol, or nil if not set
      def position_constraint_sym
        @position_constraint_sym ||= position_constraint&.to_sym
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
