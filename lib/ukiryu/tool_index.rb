# frozen_string_literal: true

# Lazy load ToolMetadata only when needed
autoload :ToolMetadata, File.expand_path('models/tool_metadata', __dir__)

module Ukiryu
  # Index for fast tool lookup by interface and alias
  #
  # This class maintains cached mappings for:
  # - Interfaces to tools (multiple tools can implement one interface)
  # - Aliases to tool names
  # - Register change detection via mtime
  #
  # Built once and cached for the lifetime of the process.
  #
  # @api private
  class ToolIndex
    class << self
      # Get the singleton instance
      #
      # @return [ToolIndex] the index instance
      def instance
        @instance ||= new
      end

      # Reset the index (mainly for testing)
      def reset
        @instance = nil
      end

      # Get all tools in the index (class method delegating to instance)
      #
      # @return [Hash{Symbol => Array<String>}] mapping of interface to tool names
      def all_tools
        instance.all_tools
      end
    end

    # Initialize the index
    #
    # @param register_path [String, nil] the path to the tool register
    def initialize(register_path: nil)
      @register_path = register_path || Ukiryu::Register.default_register_path

      if ENV['UKIRYU_DEBUG_EXECUTABLE']
        warn '[UKIRYU DEBUG ToolIndex#initialize] called'
        warn "[UKIRYU DEBUG] param register_path = #{register_path.inspect}"
        warn "[UKIRYU_DEBUG] Ukiryu::Register.default_register_path = #{Ukiryu::Register.default_register_path.inspect}"
        warn "[UKIRYU DEBUG] @register_path = #{@register_path.inspect}"
      end

      @interface_to_tools = {} # interface => [tool_names]
      @alias_to_tool = {}      # alias => [tool_names] (multiple tools can share an alias)
      @compatibility_cache = {} # tool_name => tool_definition (for platform compatibility checks)
      @built = false
      @cache_key = nil # Register state for change detection
    end

    # Find tool metadata by interface name
    # Returns the first available tool for this interface
    #
    # @param interface_name [Symbol] the interface to look up
    # @return [ToolMetadata, nil] the tool metadata or nil if not found
    def find_by_interface(interface_name)
      build_index_if_needed

      tool_names = @interface_to_tools[interface_name]
      return nil unless tool_names

      # Try each tool implementing this interface until we find one that loads
      tool_names.each do |tool_name|
        metadata = load_metadata_for_tool(tool_name)
        return metadata if metadata
      end

      nil
    end

    # Find all tools that implement an interface
    #
    # @param interface_name [Symbol] the interface to look up
    # @return [Array<String>] list of tool names implementing this interface
    def find_all_by_interface(interface_name)
      build_index_if_needed

      @interface_to_tools[interface_name] || []
    end

    # Find tool by alias
    #
    # When multiple tools have the same alias, returns the one most compatible
    # with the current platform/shell.
    #
    # @param alias_name [String] the alias to look up
    # @return [String, nil] the tool name or nil if not found
    def find_by_alias(alias_name)
      build_index_if_needed

      candidates = @alias_to_tool[alias_name.to_sym]
      return nil unless candidates

      # If only one tool has this alias, return it directly
      return candidates.first if candidates.one?

      # Multiple tools have this alias - select by platform compatibility
      runtime = Ukiryu::Runtime.instance
      platform = runtime.platform
      shell = runtime.shell

      candidates.find do |tool_name|
        tool_compatible?(tool_name, platform: platform, shell: shell)
      end || candidates.first
    end

    # Check if a tool is compatible with the given platform and shell
    #
    # @param tool_name [String, Symbol] the tool name
    # @param platform [Symbol] the platform (:macos, :linux, :windows)
    # @param shell [Symbol] the shell (:bash, :zsh, :fish, etc.)
    # @return [Boolean] true if tool has a compatible profile
    def tool_compatible?(tool_name, platform:, shell:)
      # Load tool definition to check profiles
      tool_def = load_tool_definition_for_compatibility(tool_name)
      return false unless tool_def

      # Check if any profile matches platform/shell
      tool_def.profiles&.any? do |profile|
        profile_platforms = profile.platforms ? profile.platforms.map(&:to_sym) : []
        profile_shells = profile.shells ? profile.shells.map(&:to_sym) : []

        # Empty platforms/shells means universal compatibility
        (profile_platforms.empty? || profile_platforms.include?(platform)) &&
          (profile_shells.empty? || profile_shells.include?(shell))
      end || false
    end

    # Load tool definition for compatibility checking
    # Caches loaded definitions to avoid redundant parsing
    #
    # @param tool_name [String, Symbol] the tool name
    # @return [Object, nil] the tool definition model
    def load_tool_definition_for_compatibility(tool_name)
      # Use a simple cache for compatibility checks
      @compatibility_cache ||= {}
      cache_key = tool_name.to_sym

      @compatibility_cache[cache_key] ||= begin
        yaml_content = load_yaml_for_tool(tool_name)
        return nil unless yaml_content

        Ukiryu::Models::ToolDefinition.from_yaml(yaml_content)
      end
    end

    # Get all tools in the index
    #
    # @return [Hash{Symbol => Array<String>}] mapping of interface to tool names
    def all_tools
      build_index_if_needed

      @interface_to_tools.dup
    end

    # Check if the index needs rebuilding due to register changes
    #
    # @return [Boolean] true if rebuild is needed
    def stale?
      return true unless @built

      current_cache_key = build_cache_key
      @cache_key != current_cache_key
    end

    # Update the register path
    #
    # @param new_path [String] the new register path
    def register_path=(new_path)
      return if @register_path == new_path

      @register_path = new_path
      @built = false # Rebuild index with new path
      @cache_key = nil
      @interface_to_tools = {}
      @alias_to_tool = {}
      @compatibility_cache = {}
    end

    private

    # Build index only if needed (lazy loading)
    def build_index_if_needed
      build_index if stale?
    end

    # Build cache key for register change detection
    # Uses mtime of register directory + file count for fast comparison
    #
    # @return [String] the cache key
    def build_cache_key
      current_path = register_path
      return 'empty' unless current_path

      tools_dir = File.join(current_path, 'tools')
      return 'no-tools-dir' unless Dir.exist?(tools_dir)

      # Use directory mtime and file count for change detection
      mtime = File.mtime(tools_dir).to_s
      file_count = Dir.glob(File.join(tools_dir, '*', '*.yaml')).size

      "#{mtime}-#{file_count}"
    end

    # Get the current register path
    #
    # @return [String, nil] the register path
    def register_path
      path = @register_path || Ukiryu::Register.default_register_path

      if ENV['UKIRYU_DEBUG_EXECUTABLE']
        warn '[UKIRYU DEBUG ToolIndex#register_path] called'
        warn "[UKIRYU DEBUG] @register_path = #{@register_path.inspect}"
        warn "[UKIRYU DEBUG] Ukiryu::Register.default_register_path = #{Ukiryu::Register.default_register_path.inspect}"
        warn "[UKIRYU DEBUG] returning = #{path.inspect}"
      end

      path
    end

    # Build the index by scanning tool directories
    # This is done once and cached
    def build_index
      current_path = register_path

      if ENV['UKIRYU_DEBUG_EXECUTABLE']
        warn '[UKIRYU DEBUG ToolIndex#build_index] called'
        warn "[UKIRYU DEBUG] current_path = #{current_path.inspect}"
      end

      return unless current_path

      tools_dir = File.join(current_path, 'tools')
      return unless Dir.exist?(tools_dir)

      # Clear existing indexes
      @interface_to_tools.clear
      @alias_to_tool.clear

      # Scan all tool directories for metadata
      # New structure: tools/{tool-name}/{variant}/{version}.yaml
      # Fallback: tools/{tool-name}/{version}.yaml (legacy structure)
      tool_dirs = Dir.glob(File.join(tools_dir, '*')).select { |d| File.directory?(d) }.sort

      tool_dirs.each do |tool_dir|
        tool_name = File.basename(tool_dir)
        tool_sym = tool_name.to_sym

        # Find YAML files in the tool directory (check both structures)
        yaml_files = []

        # Check for variant subdirectories (new structure: tools/ping_bsd/default/1.0.yaml)
        variant_dirs = Dir.glob(File.join(tool_dir, '*')).select { |d| File.directory?(d) }
        variant_dirs.each do |variant_dir|
          Dir.glob(File.join(variant_dir, '*.yaml')).sort.each do |file|
            yaml_files << file
          end
        end

        # Fallback: direct YAML files in tool directory (legacy structure)
        if yaml_files.empty?
          Dir.glob(File.join(tool_dir, '*.yaml')).sort.each do |file|
            yaml_files << file
          end
        end

        # Process each YAML file (use the latest/highest version file)
        yaml_files.each do |file|
          # Load only the top-level keys (metadata) without full parsing
          hash = YAML.safe_load(File.read(file), permitted_classes: [Symbol], aliases: true)
          next unless hash

          # Index by interface (multiple tools can implement one interface)
          # v2: implements is an array, v1: implements is a string
          implements_value = hash['implements']
          if implements_value
            interfaces = if implements_value.is_a?(Array)
                           implements_value.map(&:to_sym)
                         else
                           [implements_value.to_sym]
                         end

            interfaces.each do |interface_sym|
              @interface_to_tools[interface_sym] ||= []
              @interface_to_tools[interface_sym] << tool_sym unless @interface_to_tools[interface_sym].include?(tool_sym)
            end
          end

          # Index by alias (multiple tools can have the same alias)
          aliases = hash['aliases']
          next unless aliases.respond_to?(:each)

          aliases.each do |alias_name|
            @alias_to_tool[alias_name.to_sym] ||= []
            @alias_to_tool[alias_name.to_sym] << tool_sym unless @alias_to_tool[alias_name.to_sym].include?(tool_sym)
          end
        end
      rescue StandardError => e
        # Skip files that can't be parsed
        warn "Warning: Failed to parse #{tool_name}: #{e.message}"
      end

      @cache_key = build_cache_key
      @built = true
    end

    # Load metadata for a specific tool
    #
    # @param tool_name [Symbol, String] the tool name
    # @return [ToolMetadata, nil] the tool metadata
    def load_metadata_for_tool(tool_name)
      yaml_content = load_yaml_for_tool(tool_name)
      return nil unless yaml_content

      hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
      return nil unless hash

      ToolMetadata.from_hash(hash, tool_name: tool_name.to_s, register_path: register_path)
    end

    # Load YAML content for a specific tool
    #
    # @param tool_name [Symbol, String] the tool name
    # @return [String, nil] the YAML content
    def load_yaml_for_tool(tool_name)
      current_path = register_path

      if ENV['UKIRYU_DEBUG_EXECUTABLE']
        warn "[UKIRYU DEBUG ToolIndex#load_yaml_for_tool] tool_name=#{tool_name}"
        warn "[UKIRYU DEBUG] current_path = #{current_path.inspect}"
      end

      return nil unless current_path

      tool_dir = File.join(current_path, 'tools', tool_name.to_s)
      return nil unless Dir.exist?(tool_dir)

      # Search for version files in both structures:
      # New: tools/{tool-name}/{variant}/{version}.yaml
      # Legacy: tools/{tool-name}/{version}.yaml

      # First check for variant subdirectories (new structure)
      variant_dirs = Dir.glob(File.join(tool_dir, '*')).select { |d| File.directory?(d) }

      variant_dirs.each do |variant_dir|
        # Prefer 'default' variant if present
        next unless File.basename(variant_dir) == 'default'

        files = Dir.glob(File.join(variant_dir, '*.yaml')).sort
        return File.read(files.last) if files.any?

        # Fall back to any variant directory
        files = Dir.glob(File.join(variant_dir, '*.yaml')).sort
        return File.read(files.last) if files.any?
      end

      # Fallback: direct YAML files in tool directory (legacy structure)
      files = Dir.glob(File.join(tool_dir, '*.yaml')).sort
      files.last ? File.read(files.last) : nil
    rescue StandardError
      nil
    end
  end
end
