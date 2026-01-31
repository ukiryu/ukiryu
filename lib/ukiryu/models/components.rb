# frozen_string_literal: true

module Ukiryu
  module Models
    # Components register for reusable definitions
    #
    # Enables sharing common option/argument/flag/exit_codes definitions
    # across commands through `$ref` references.
    #
    # @example
    #   components = Components.new(
    #     options: { 'verbose' => OptionDefinition.new(...) },
    #     flags: { 'help' => FlagDefinition.new(...) }
    #   )
    class Components < Lutaml::Model::Serializable
      attribute :options, :hash, default: {}
      attribute :flags, :hash, default: {}
      attribute :arguments, :hash, default: {}
      attribute :exit_codes, Ukiryu::Models::ExitCodes

      key_value do
        map 'options', to: :options
        map 'flags', to: :flags
        map 'arguments', to: :arguments
        map 'exit_codes', to: :exit_codes
      end

      # Get an option by name
      #
      # @param name [String, Symbol] the option name
      # @return [OptionDefinition, nil] the option definition
      def option(name)
        @options&.dig(name.to_s)
      end

      # Get a flag by name
      #
      # @param name [String, Symbol] the flag name
      # @return [FlagDefinition, nil] the flag definition
      def flag(name)
        @flags&.dig(name.to_s)
      end

      # Get an argument by name
      #
      # @param name [String, Symbol] the argument name
      # @return [ArgumentDefinition, nil] the argument definition
      def argument(name)
        @arguments&.dig(name.to_s)
      end

      # Check if a reference can be resolved
      #
      # @param ref [String] the reference path (e.g., '#/components/options/verbose')
      # @return [Boolean] true if the reference can be resolved
      def can_resolve?(ref)
        return false unless ref =~ %r{^#/components/(options|flags|arguments|exit_codes)/(.+)$}

        type = Regexp.last_match(1)
        name = Regexp.last_match(2)

        case type
        when 'options'
          @options&.key?(name)
        when 'flags'
          @flags&.key?(name)
        when 'arguments'
          @arguments&.key?(name)
        when 'exit_codes'
          !@exit_codes.nil?
        else
          false
        end
      end

      # Resolve a reference path to a component
      #
      # @param ref [String] the reference path (e.g., '#/components/options/verbose')
      # @return [Object, nil] the component or nil if not found
      def resolve(ref)
        return nil unless ref =~ %r{^#/components/(options|flags|arguments|exit_codes)/(.+)$}

        type = Regexp.last_match(1)
        name = Regexp.last_match(2)

        case type
        when 'options'
          option(name)
        when 'flags'
          flag(name)
        when 'arguments'
          argument(name)
        when 'exit_codes'
          @exit_codes
        end
      end
    end
  end
end
