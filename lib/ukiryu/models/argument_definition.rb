# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Argument definition for a command
    #
    # @example
    #   arg = ArgumentDefinition.new(
    #     name: 'input',
    #     type: 'file',
    #     variadic: true,
    #     position: 'last'
    #   )
    class ArgumentDefinition < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :type, :string, default: 'string'
      attribute :required, :boolean, default: false
      attribute :position, :string, default: '99'
      attribute :variadic, :boolean, default: false
      attribute :min, :integer
      attribute :max, :integer
      # Can be Integer or Array[Integer]
      attribute :size, :integer, collection: true
      # Type of array elements
      attribute :of, :string
      # Array for numeric range [min, max]
      attribute :range, :integer, collection: true
      # Valid values for symbols
      attribute :values, :string, collection: true
      attribute :separator, :string, default: ' '
      attribute :format, :string
      attribute :description, :string

      yaml do
        map_element 'name', to: :name
        map_element 'type', to: :type
        map_element 'required', to: :required
        map_element 'position', to: :position
        map_element 'variadic', to: :variadic
        map_element 'min', to: :min
        map_element 'max', to: :max
        map_element 'size', to: :size
        map_element 'of', to: :of
        map_element 'range', to: :range
        map_element 'values', to: :values
        map_element 'separator', to: :separator
        map_element 'format', to: :format
        map_element 'description', to: :description
      end

      # Check if this is the last argument
      #
      # @return [Boolean] true if position is :last
      def last?
        position == 'last'
      end

      # Get the position as symbol or integer
      #
      # @return [Symbol, Integer] the parsed position
      def parsed_position
        case position
        when 'last'
          :last
        when 'first'
          :first
        when /^\d+$/
          position.to_i
        else
          99
        end
      end

      # Get numeric position for sorting
      #
      # @return [Integer] the numeric position
      def numeric_position
        case position
        when 'last'
          999
        when 'first'
          1
        when /^\d+$/
          position.to_i
        else
          99
        end
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

      # Get type as symbol (cached for performance)
      #
      # @return [Symbol] the type as symbol
      def type_sym
        @type_sym ||= type.to_sym
      end
    end
  end
end
