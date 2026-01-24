# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  class ToolMetadata
    # Lightweight metadata model for tools
    # Contains only the essential information needed for tool discovery
    # without loading the full profile definition

    attr_reader :name, :version, :display_name, :implements, :homepage,
                :description, :aliases, :tool_name, :register_path, :default_command

    def initialize(name:, version:, display_name: nil, implements: nil,
                   homepage: nil, description: nil, aliases: nil,
                   tool_name: nil, register_path: nil, default_command: nil)
      @name = name
      @version = version
      @display_name = display_name
      @implements = implements
      @homepage = homepage
      @description = description
      @aliases = Array(aliases || [])
      @tool_name = tool_name || name
      @register_path = register_path
      @default_command = default_command
    end

    # Check if this metadata matches an interface
    #
    # @param interface_name [Symbol, String] the interface to check
    # @return [Boolean] true if this tool implements the interface
    def implements?(interface_name)
      @implements == interface_name.to_sym
    end

    # Get the primary command name for this tool
    # Returns the default_command from YAML if set, otherwise the implements value,
    # otherwise falls back to the tool name
    #
    # @return [Symbol, nil] the default command name
    def default_command
      @default_command || @implements || @name.to_sym
    end

    # String representation
    #
    # @return [String] description string
    def to_s
      "#{@display_name || @name} v#{@version}"
    end

    # Inspect
    #
    # @return [String] inspection string
    def inspect
      "#<#{self.class.name} name=#{@name.inspect} version=#{@version.inspect} implements=#{@implements.inspect}>"
    end

    # Class method to create from YAML hash
    # Extracts only metadata fields from a full tool profile
    #
    # @param hash [Hash] the YAML profile hash
    # @param tool_name [String] the tool name
    # @param register_path [String] the register path
    # @return [ToolMetadata] the metadata object
    def self.from_hash(hash, tool_name:, register_path: nil)
      new(
        name: tool_name,
        version: hash['version'],
        display_name: hash['display_name'],
        implements: hash['implements']&.to_sym,
        homepage: hash['homepage'],
        description: hash['description'],
        aliases: hash['aliases'],
        default_command: hash['default_command'],
        tool_name: tool_name,
        register_path: register_path
      )
    end
  end
end
