# frozen_string_literal: true

module Ukiryu
  module Models
    # Interface model representing a pure contract for tool implementations.
    #
    # An Interface defines WHAT actions a tool must provide, without specifying
    # HOW those actions are implemented. It's the "interface" in interface-centric design.
    #
    # @example Interface for gzip compression
    #   interface = Interface.new(
    #     name: :gzip,
    #     version: "1.0",
    #     display_name: "Gzip Compression",
    #     actions: [
    #       { name: :compress, signature: { inputs: [...], output: {...} } },
    #       { name: :decompress, signature: { input: {...} } }
    #     ],
    #     aliases: [:gzip, :gunzip, :gzcat]
    #   )
    #
    # @attr name [Symbol] Interface identifier
    # @attr version [String] Interface version (for contract evolution)
    # @attr display_name [String] Human-readable name
    # @attr actions [Array<Hash>] Action contracts (signatures)
    # @attr aliases [Array<Symbol>] Alternative tool names
    class Interface
      attr_reader :name, :version, :display_name, :actions, :aliases

      # @param name [Symbol] Interface identifier
      # @param version [String] Interface version
      # @param display_name [String, nil] Human-readable name
      # @param actions [Array<Hash>] Action contracts
      # @param aliases [Array<Symbol>] Alternative names
      def initialize(name:, version:, actions:, display_name: nil, aliases: [])
        @name = name
        @version = version
        @display_name = display_name || name.to_s.capitalize
        @actions = actions
        @aliases = aliases
        freeze
      end

      # Get an action by name
      #
      # @param action_name [Symbol] Action name
      # @return [Hash, nil] Action contract or nil
      def action(action_name)
        @actions.find { |a| a[:name] == action_name }
      end

      # Check if interface has an action
      #
      # @param action_name [Symbol] Action name
      # @return [Boolean] true if action exists
      def action?(action_name)
        !action(action_name).nil?
      end

      # Load interface from YAML file
      #
      # @param path [String] Path to interface YAML file
      # @return [Interface] Loaded interface
      def self.from_yaml(path)
        require 'psych'
        data = Psych.safe_load_file(path, permitted_classes: [Symbol, String, Integer, Array, Hash, TrueClass, FalseClass])
        from_hash(symbolize_keys(data))
      end

      # Symbolize hash keys recursively
      #
      # @param hash [Hash] hash with string keys
      # @return [Hash] hash with symbolized keys
      def self.symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym).transform_values do |v|
          case v
          when Hash
            symbolize_keys(v)
          when Array
            v.map { |item| item.is_a?(Hash) ? symbolize_keys(item) : item }
          else
            v
          end
        end
      end

      # Create interface from hash
      #
      # @param data [Hash] Interface data
      # @return [Interface] Created interface
      def self.from_hash(data)
        new(
          name: data[:name],
          version: data[:version],
          display_name: data[:display_name],
          actions: data[:actions],
          aliases: Array(data[:aliases] || []).map(&:to_sym)
        )
      end

      # String representation
      #
      # @return [String]
      def to_s
        "#{@name}/#{@version}"
      end

      # Inspect representation
      #
      # @return [String]
      def inspect
        "#<Ukiryu::Models::Interface #{self} actions=#{@actions.length}>"
      end
    end
  end
end
