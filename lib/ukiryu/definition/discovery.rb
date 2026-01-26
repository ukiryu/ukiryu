# frozen_string_literal: true

require_relative 'metadata'
require_relative 'loader'

module Ukiryu
  module Definition
    # Discover tool definitions in standard filesystem locations
    #
    # This class searches for tool definitions in XDG-compliant paths
    # and tool-bundled locations.
    class Discovery
      # User data directory (XDG_DATA_HOME or ~/.local/share)
      #
      # @return [String] user data directory
      def self.xdg_data_home
        ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share'))
      end

      # System data directories (XDG_DATA_DIRS or /usr/local/share:/usr/share)
      #
      # @return [Array<String>] system data directories
      def self.xdg_data_dirs
        if ENV.key?('XDG_DATA_DIRS')
          ENV.fetch('XDG_DATA_DIRS', '').split(':').map(&:strip).reject(&:empty?)
        else
          ['/usr/local/share', '/usr/share']
        end
      end

      # Get the user definitions directory
      #
      # @return [String] path to user definitions directory
      def self.user_definitions_directory
        File.join(xdg_data_home, 'ukiryu', 'definitions')
      end

      # Get all search paths for definitions
      #
      # Returns paths in priority order (highest priority first):
      # 1. User definitions
      # 2. Tool-bundled paths (dynamically discovered)
      # 3. Local system definitions
      # 4. System definitions
      #
      # @return [Array<String>] search paths
      def self.search_paths
        paths = []

        # 1. User definitions (highest priority after explicit flag)
        paths << user_definitions_directory

        # 2. Tool-bundled paths (dynamically discovered)
        paths.concat(tool_bundled_paths)

        # 3. Local system definitions
        xdg_data_dirs.each do |dir|
          paths << File.join(dir, 'ukiryu', 'definitions')
        end

        # 4. System definitions
        paths << File.join(xdg_data_home, 'ukiryu', 'definitions')

        paths.uniq
      end

      # Get tool-bundled definition paths
      #
      # Searches for tool installations and checks for bundled definitions
      #
      # @return [Array<String>] tool-bundled paths
      def self.tool_bundled_paths
        paths = []

        # Check PATH for tool installations
        ENV.fetch('PATH', '').split(':').each do |bin_dir|
          next unless File.directory?(bin_dir)

          # Check for ukiryu subdirectory alongside bin
          parent_dir = File.dirname(bin_dir)
          ukiryu_dir = File.join(parent_dir, 'ukiryu')
          paths << ukiryu_dir if File.directory?(ukiryu_dir)

          # Check for share/ukiryu subdirectory
          share_dir = File.join(parent_dir, 'share', 'ukiryu')
          paths << share_dir if File.directory?(share_dir)
        end

        # Check /opt directory structure
        opt_paths = Dir.glob('/opt/*/ukiryu').select { |d| File.directory?(d) }
        paths.concat(opt_paths)

        paths.uniq
      end

      # Discover all available definitions
      #
      # Searches all paths for tool definitions and returns metadata
      #
      # @return [Hash<String, Array<DefinitionMetadata>>] hash of tool names to metadata
      def self.discover
        definitions = Hash.new { |h, k| h[k] = [] }

        search_paths.each do |search_path|
          next unless File.directory?(search_path)

          discover_in_path(search_path).each do |metadata|
            definitions[metadata.name] << metadata
          end
        end

        # Sort each tool's definitions by priority
        definitions.each_value(&:sort!)

        definitions
      end

      # Find the best definition for a tool
      #
      # @param tool_name [String] the tool name
      # @param version [String, nil] optional version constraint
      # @return [DefinitionMetadata, nil] the best matching definition, or nil
      def self.find(tool_name, version = nil)
        definitions = discover[tool_name]
        return nil if definitions.nil? || definitions.empty?

        if version
          # Find exact version match
          definitions.find { |d| d.version == version }
        else
          # Return highest priority definition
          definitions.first
        end
      end

      # List all discovered tool names
      #
      # @return [Array<String>] tool names
      def self.available_tools
        discover.keys.sort
      end

      # Get all definitions for a specific tool
      #
      # @param tool_name [String] the tool name
      # @return [Array<DefinitionMetadata>] array of definitions
      def self.definitions_for(tool_name)
        discover[tool_name] || []
      end

      # Discover definitions in a specific path
      #
      # @param search_path [String] the path to search
      # @return [Array<DefinitionMetadata>] array of discovered metadata
      def self.discover_in_path(search_path)
        definitions = []

        # Determine source type based on path
        source_type = determine_source_type(search_path)

        # Look for tool subdirectories (structure: {tool}/{version}.yaml)
        if File.directory?(search_path)
          Dir.foreach(search_path) do |tool_name|
            next if tool_name.start_with?('.')

            tool_dir = File.join(search_path, tool_name)
            next unless File.directory?(tool_dir)

            # Find YAML files in tool directory
            Dir.glob(File.join(tool_dir, '*.yaml')).each do |yaml_file|
              metadata = metadata_from_file(yaml_file, source_type)
              definitions << metadata if metadata
            rescue StandardError => e
              # Skip invalid files silently
              warn "[Ukiryu] Skipping invalid definition #{yaml_file}: #{e.message}"
            end
          end
        end

        # Also check for flat YAML files (structure: {tool}-{version}.yaml or {version}.yaml)
        Dir.glob(File.join(search_path, '*-*.yaml')).each do |yaml_file|
          metadata = metadata_from_file(yaml_file, source_type)
          definitions << metadata if metadata
        rescue StandardError => e
          # Skip invalid files silently
          warn "[Ukiryu] Skipping invalid definition #{yaml_file}: #{e.message}"
        end

        definitions
      end

      # Determine the source type for a search path
      #
      # @param path [String] the search path
      # @return [Symbol] source type
      def self.determine_source_type(path)
        expanded = File.expand_path(path)

        if expanded.include?(xdg_data_home)
          :user
        elsif expanded.include?('/opt/')
          :bundled
        elsif expanded.include?('/usr/local/share')
          :local_system
        elsif expanded.include?('/usr/share')
          :system
        else
          :bundled # Default to bundled for unknown paths
        end
      end

      # Create metadata from a YAML file
      #
      # @param yaml_file [String] path to the YAML file
      # @param source_type [Symbol] source type
      # @return [DefinitionMetadata, nil] metadata or nil if invalid
      def self.metadata_from_file(yaml_file, source_type)
        # Try to load just the name and version from YAML
        yaml_content = File.read(yaml_file)
        data = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)

        return nil unless data.is_a?(Hash)
        return nil unless data['name']

        name = data['name']
        version = data['version'] || '1.0' # Default version

        DefinitionMetadata.new(
          name: name,
          version: version,
          path: yaml_file,
          source_type: source_type
        )
      rescue Psych::SyntaxError, StandardError
        nil
      end
    end
  end
end
