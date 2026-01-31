# frozen_string_literal: true

module Ukiryu
  class ToolMetadata < Lutaml::Model::Serializable
    # Lightweight metadata model for tools
    # Contains only the essential information needed for tool discovery
    # without loading the full profile definition

    # @return [String] tool name
    # @return [String] tool version
    # @return [String, nil] display name
    # @return [String, nil] interface this tool implements
    # @return [String, nil] interface version
    # @return [String, nil] homepage URL
    # @return [String, nil] description
    # @return [Array<String>] aliases
    # @return [String] tool name (may differ from name)
    # @return [String, nil] register path
    # @return [Symbol, nil] default command
    # @return [Array<Symbol>] list of tools this may provide
    # @return [Symbol, nil] parent tool this is backed by

    attribute :name, :string
    attribute :version, :string
    attribute :display_name, :string
    attribute :implements, :string
    attribute :implements_version, :string
    attribute :homepage, :string
    attribute :description, :string
    attribute :aliases, :string, default: -> { [] }
    attribute :tool_name, :string
    attribute :register_path, :string
    attribute :default_command, :string
    attribute :may_provide, :string, default: -> { [] }
    attribute :backed_by, :string

    # Get the full implements reference (interface@version)
    #
    # @return [String, nil] the implements reference
    def implements_ref
      return nil unless implements && implements_version

      "#{implements}@#{implements_version}"
    end

    # Check if this metadata matches an interface
    #
    # @param interface_name [Symbol, String] the interface to check
    # @param version [String, nil] optional version to match
    # @return [Boolean] true if this tool implements the interface (and version if specified)
    def implements?(interface_name, version: nil)
      return false unless implements

      matches_interface = implements.to_sym == interface_name.to_sym || implements == interface_name.to_s

      if version
        matches_interface && implements_version == version
      else
        matches_interface
      end
    end

    # Get the primary command name for this tool
    # Returns the default_command from YAML if set, otherwise the implements value,
    # otherwise falls back to the tool name
    #
    # @return [Symbol, nil] the default command name
    def default_command
      @default_command&.to_sym || implements&.to_sym || name&.to_sym
    end

    # Get may_provide as symbols
    #
    # @return [Array<Symbol>] may_provide list as symbols
    def may_provide_list
      Array(may_provide).map(&:to_sym)
    end

    # Get tool_name, defaulting to name if not set
    #
    # @return [String] the tool name
    def tool_name
      @tool_name || name
    end

    # Get aliases, ensuring it's always an array
    #
    # @return [Array<String>] the aliases as an array
    def aliases
      Array(@aliases || [])
    end

    # Get backed_by as symbol
    #
    # @return [Symbol, nil] backed_by as symbol
    def backing_tool
      backed_by&.to_sym
    end

    # String representation
    #
    # @return [String] description string
    def to_s
      "#{display_name || name} v#{version}"
    end

    # Inspect
    #
    # @return [String] inspection string
    def inspect
      "#<#{self.class.name} name=#{name.inspect} version=#{version.inspect} implements=#{implements.inspect}>"
    end

    # Parse implements field in format "interface@version" or "interface"
    #
    # @param implements_value [String, nil] the implements value from YAML
    # @return [Array<String, nil>] interface and version
    def self.parse_implements(implements_value)
      return [nil, nil] unless implements_value

      if implements_value.to_s.include?('@')
        implements_value.to_s.split('@', 2)
      else
        [implements_value.to_s, nil]
      end
    end

    # Class method to create from YAML hash
    # Extracts only metadata fields from a full tool profile
    #
    # @param hash [Hash] the YAML profile hash
    # @param tool_name [String] the tool name
    # @param register_path [String] the register path
    # @return [ToolMetadata] the metadata object
    def self.from_hash(hash, tool_name:, register_path: nil)
      implements_val = hash['implements']
      interface, version = parse_implements(implements_val)

      new(
        name: tool_name,
        version: hash['version'],
        display_name: hash['display_name'],
        implements: interface,
        implements_version: version,
        homepage: hash['homepage'],
        description: hash['description'],
        aliases: hash['aliases'] || [],
        tool_name: tool_name,
        register_path: register_path,
        default_command: hash['default_command'],
        may_provide: hash['may_provide'] || [],
        backed_by: hash['backed_by']
      )
    end
  end
end
