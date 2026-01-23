# frozen_string_literal: true

module Ukiryu
  module Models
    # Represents a command routing table for hierarchical tools.
    #
    # Routing maps command names to their executable targets, enabling
    # tools like git where `git remote` routes to `git-remote` executable.
    #
    # @example Basic routing
    #   routing = Routing.new({ 'remote' => 'git-remote', 'branch' => 'git-branch' })
    #   routing.resolve('remote') # => 'git-remote'
    #
    # @example Multi-level routing
    #   routing = Routing.new({ 'remote' => 'git-remote' })
    #   routing.child('remote').merge!({ 'add' => 'action' })
    #   routing.resolve_path(['remote', 'add']) # => ['git-remote', 'action']
    #
    class Routing
      # The routing table mapping command names to executables
      #
      # @return [Hash<String, String>]
      attr_reader :table

      # Parent routing table for multi-level hierarchies
      #
      # @return [Routing, nil]
      attr_reader :parent

      # Create a new Routing table
      #
      # @param table [Hash] routing table mapping command names to executables
      # @param parent [Routing, nil] parent routing for multi-level hierarchies
      #
      # @example
      #   Routing.new({ 'remote' => 'git-remote' })
      #   Routing.new({ 'add' => 'action' }, parent_routing)
      #
      def initialize(table = {}, parent: nil)
        @table = symbolize_keys(table)
        @parent = parent
        @children = {}
      end

      # Resolve a command name to its executable target
      #
      # @param command_name [String, Symbol] the command name to resolve
      # @return [String, nil] the executable target or nil if not found
      #
      # @example
      #   routing.resolve('remote') # => 'git-remote'
      #   routing.resolve('unknown') # => nil
      #
      def resolve(command_name)
        key = command_name.to_sym
        @table[key] || @parent&.resolve(key)
      end

      # Resolve a path of command names to their executable targets
      #
      # @param path [Array<String, Symbol>] the command path to resolve
      # @return [Array<String>] array of executable targets
      #
      # @example
      #   routing.resolve_path(['remote', 'add']) # => ['git-remote', 'action']
      #
      def resolve_path(path)
        return [] if path.empty?

        # Resolve first level in this routing table
        first_target = resolve(path.first)
        return [] unless first_target

        # If there are more levels, resolve them in child routing
        if path.size > 1
          child = child(path.first)
          [first_target, *child.resolve_path(path[1..])]
        else
          [first_target]
        end
      end

      # Check if a command exists in the routing table
      #
      # @param command_name [String, Symbol] the command name to check
      # @return [Boolean] true if the command exists
      #
      # @example
      #   routing.include?('remote') # => true
      #   routing.include?('unknown') # => false
      #
      def include?(command_name)
        key = command_name.to_sym
        @table.key?(key) || @parent&.include?(key) || false
      end

      # Get a child routing table for a command
      #
      # Creates or returns the child routing for multi-level hierarchies.
      #
      # @param command_name [String, Symbol] the parent command name
      # @return [Routing] the child routing table
      #
      # @example
      #   routing.child('remote').merge!({ 'add' => 'action' })
      #
      def child(command_name)
        key = command_name.to_sym
        @children[key] ||= Routing.new(parent: self)
      end

      # Merge a hash into this routing table
      #
      # @param other [Hash] the routing entries to merge
      # @return [self] returns self for chaining
      #
      # @example
      #   routing.merge!({ 'branch' => 'git-branch' })
      #
      def merge!(other)
        @table.merge!(symbolize_keys(other))
        self
      end

      # Get all command names in this routing table
      #
      # @return [Array<String>] array of command names
      #
      # @example
      #   routing.keys # => ['remote', 'branch', 'stash']
      #
      def keys
        @table.keys.map(&:to_s).sort
      end

      # Check if the routing table is empty
      #
      # @return [Boolean] true if no routing entries
      #
      def empty?
        @table.empty?
      end

      # Get the number of routing entries
      #
      # @return [Integer] number of entries
      #
      def size
        @table.size
      end

      # Convert routing table to hash
      #
      # @return [Hash] the routing table as a hash
      #
      def to_h
        @table.transform_keys(&:to_s)
      end

      # Check for circular references in routing hierarchy
      #
      # @return [Boolean] true if circular reference detected
      #
      def circular?
        return false unless @parent

        current = @parent
        seen = { self => true }

        while current
          return true if seen.key?(current)

          seen[current] = true
          current = current.parent
        end

        false
      end

      # String representation
      #
      # @return [String] debug-friendly string representation
      #
      def inspect
        parent_info = @parent ? "(parent: #{parent.object_id})" : ''
        "#<#{self.class.name}:#{object_id}#{parent_info} #{@table.keys.inspect}>"
      end

      # String representation for debugging
      #
      # @return [String] routing table as formatted string
      #
      def to_s
        return "(empty)" if @table.empty?

        @table.map { |k, v| "#{k} => #{v}" }.join(', ')
      end

      private

      # Symbolize hash keys
      #
      # @param hash [Hash] the hash to symbolize
      # @return [Hash] hash with symbolized keys
      #
      def symbolize_keys(hash)
        hash.transform_keys(&:to_sym)
      end
    end
  end
end
