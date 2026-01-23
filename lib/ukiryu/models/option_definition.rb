# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Option definition for a command
    #
    # Represents a named option (flag with value)
    #
    # @example
    #   opt = OptionDefinition.new(
    #     name: 'quality',
    #     cli: '-q',
    #     type: 'integer',
    #     format: 'single_dash_space',
    #     description: 'JPEG quality'
    #   )
    class OptionDefinition < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :cli, :string
      attribute :type, :string, default: 'string'
      attribute :format, :string, default: 'single_dash_space'
      attribute :separator, :string
      attribute :default, :string
      # Array for numeric range [min, max]
      attribute :range, :integer, collection: true
      # Valid values for symbols
      attribute :values, :string, collection: true
      # Type of array elements
      attribute :of, :string
      attribute :description, :string
      attribute :platforms, :string, collection: true, default: []

      yaml do
        map_element 'name', to: :name
        map_element 'cli', to: :cli
        map_element 'type', to: :type
        map_element 'format', to: :format
        map_element 'separator', to: :separator
        map_element 'default', to: :default
        map_element 'range', to: :range
        map_element 'values', to: :values
        map_element 'of', to: :of
        map_element 'description', to: :description
        map_element 'platforms', to: :platforms
      end

      # Check if option applies to a platform
      #
      # @param platform [Symbol] the platform
      # @return [Boolean] true if applies
      def applies_to?(platform)
        return true if platforms.nil? || platforms.empty?

        cached_platforms_sym.include?(platform.to_sym)
      end

      # Check if type is boolean
      #
      # @return [Boolean] true if boolean type
      def boolean?
        type == 'boolean'
      end

      # Get format as symbol (cached for performance)
      #
      # @return [Symbol] the format
      def format_sym
        @format_sym ||= format&.to_sym || :single_dash_space
      end

      # Hash-like access for Type validation compatibility
      #
      # @param key [Symbol, String] the attribute key
      # @return [Object] the attribute value
      def [](key)
        key_sym = key.to_sym
        # Return nil for unknown keys (like Type validation options)
        return nil unless respond_to?(key_sym, true)

        send(key_sym)
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
