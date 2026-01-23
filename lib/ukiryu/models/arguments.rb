# frozen_string_literal: true

require 'lutaml/model'
require_relative 'argument'

module Ukiryu
  module Models
    # Structured command arguments
    #
    # Contains the structured arguments passed to a command execution.
    # Each argument has a name, value, and type.
    class Arguments < Lutaml::Model::Serializable
      attribute :options, Argument, collection: true, initialize_empty: true
      attribute :flags, :string, collection: true, default: []
      attribute :positional, Argument, collection: true, initialize_empty: true

      yaml do
        map_element 'options', to: :options
        map_element 'flags', to: :flags
        map_element 'positional', to: :positional
      end

      json do
        map 'options', to: :options
        map 'flags', to: :flags
        map 'positional', to: :positional
      end

      # Create Arguments from a hash of parameters
      #
      # @param params [Hash] the parameters hash
      # @param command_definition [CommandDefinition] the command definition for context
      # @return [Arguments] the arguments model
      def self.from_params(params, command_definition = nil)
        options_arr = []
        flags_arr = []
        positional_arr = []

        params.each do |key, value|
          # Determine argument type based on command definition or heuristics
          arg_type = determine_argument_type(key, value, command_definition)

          case arg_type
          when :flag
            # Boolean flags
            flags_arr << key.to_s if value
          when :option
            # Named options with values
            options_arr << Argument.new(name: key.to_s, value: stringify_value(value), type: 'option')
          when :positional
            # Positional arguments
            positional_arr << Argument.new(name: key.to_s, value: stringify_value(value), type: 'positional')
          end
        end

        # Set arrays directly to ensure proper serialization
        args = new
        args.options = options_arr unless options_arr.empty?
        args.flags = flags_arr unless flags_arr.empty?
        args.positional = positional_arr unless positional_arr.empty?

        args
      end

      # Determine the type of an argument
      #
      # @param key [Symbol] the argument key
      # @param value [Object] the argument value
      # @param command_definition [CommandDefinition] the command definition
      # @return [Symbol] :option, :flag, or :positional
      def self.determine_argument_type(key, value, command_definition)
        # Check command definition if available
        if command_definition
          flag_def = command_definition.flags&.find { |f| f.name.to_sym == key }
          return :flag if flag_def

          option_def = command_definition.options&.find { |o| o.name.to_sym == key }
          return :option if option_def

          arg_def = command_definition.arguments&.find { |a| a.name.to_sym == key }
          return :positional if arg_def
        end

        # Fall back to heuristics
        if value.is_a?(TrueClass) || value.is_a?(FalseClass)
          :flag
        elsif value.is_a?(Array)
          # Arrays are typically options (like inputs)
          :option
        else
          :option
        end
      end

      # Convert a value to string for serialization
      #
      # @param value [Object] the value
      # @return [String] string representation
      def self.stringify_value(value)
        case value
        when Array
          value.map(&:to_s).join(', ')
        when Symbol, Integer, Float, TrueClass, FalseClass
          value.to_s
        when NilClass
          ''
        else
          value.to_s
        end
      end
    end
  end
end
