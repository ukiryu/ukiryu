# frozen_string_literal: true

require_relative 'interface'
require_relative '../utils'

module Ukiryu
  module Models
    # ImplementationIndex model for routing to specific tool implementations.
    #
    # The ImplementationIndex defines which implementations exist for a tool,
    # how to detect them, their version schemes, and version-to-file routing.
    #
    # @example
    #   index = ImplementationIndex.new(
    #     name: :gzip,
    #     interface: :gzip,
    #     interface_version: "1.0",
    #     implementations: [
    #       {
    #         name: :gnu,
    #         detection: { command: ["--version"], pattern: "GNU gzip (.+)" },
    #         version_scheme: :semantic,
    #         versions: [{ equals: "1.12.0", file: "gnu/1.12.yaml" }],
    #         default: "gnu/1.12.yaml"
    #       }
    #     ]
    #   )
    #
    # @attr name [Symbol] Tool identifier
    # @attr interface [Symbol] Interface this tool implements
    # @attr interface_version [String] Interface version
    # @attr implementations [Array<Hash>] Implementation definitions
    class ImplementationIndex
      attr_reader :name, :interface, :interface_version, :implementations

      # @param name [Symbol] Tool identifier
      # @param interface [Symbol] Interface this tool implements
      # @param interface_version [String] Interface version (default: "1.0")
      # @param implementations [Array<Hash>] Implementation definitions
      def initialize(name:, interface:, implementations:, interface_version: '1.0')
        @name = name
        @interface = interface
        @interface_version = interface_version
        @implementations = implementations.map { |impl| symbolize_hash(impl) }
        freeze
      end

      # Get an implementation by name
      #
      # @param impl_name [Symbol] Implementation name
      # @return [Hash, nil] Implementation or nil
      def implementation(impl_name)
        @implementations.find { |impl| impl[:name] == impl_name }
      end

      # Get all implementation names
      #
      # @return [Array<Symbol>] Implementation names
      def implementation_names
        @implementations.map { |impl| impl[:name] }
      end

      # Load ImplementationIndex from YAML file
      #
      # @param path [String] Path to index YAML file
      # @return [ImplementationIndex] Loaded index
      def self.from_yaml(path)
        require 'psych'
        data = Psych.safe_load_file(path,
                                    permitted_classes: [Symbol, String, Integer, Array, Hash, TrueClass, FalseClass])
        from_hash(data)
      end

      # Create ImplementationIndex from hash
      #
      # @param data [Hash] Index data
      # @return [ImplementationIndex] Created index
      def self.from_hash(data)
        new(
          name: data[:name],
          interface: data[:interface],
          interface_version: data[:interface_version] || '1.0',
          implementations: data[:implementations] || []
        )
      end

      # String representation
      #
      # @return [String]
      def to_s
        "#{@name} (implements #{@interface}/#{@interface_version})"
      end

      # Inspect representation
      #
      # @return [String]
      def inspect
        "#<Ukiryu::Models::ImplementationIndex #{self} implementations=#{@implementations.length}>"
      end

      private

      # Symbolize hash keys recursively
      #
      # @param hash [Hash] hash to symbolize
      # @return [Hash] hash with symbolized keys
      def symbolize_hash(hash)
        Utils.symbolize_keys(hash)
      end
    end
  end
end
