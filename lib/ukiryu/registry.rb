# frozen_string_literal: true

require "yaml"
require "find"

module Ukiryu
  # YAML profile registry loader
  #
  # Loads tool definitions from YAML profiles in a registry directory.
  class Registry
    class << self
      # Load all tool profiles from a registry directory
      #
      # @param path [String] the registry directory path
      # @param options [Hash] loading options
      # @option options [Boolean] :recursive search recursively (default: true)
      # @option options [Boolean] :validate validate against schema (default: false)
      # @return [Hash] loaded tools keyed by name
      def load_from(path, options = {})
        raise ProfileLoadError, "Registry path not found: #{path}" unless Dir.exist?(path)

        tools = {}
        recursive = options.fetch(:recursive, true)

        pattern = recursive ? "**/*.yaml" : "*.yaml"
        files = Dir.glob(File.join(path, "tools", pattern))

        files.each do |file|
          begin
            profile = load_profile(file)
            name = profile[:name]
            tools[name] ||= []
            tools[name] << profile
          rescue => e
            warn "Warning: Failed to load profile #{file}: #{e.message}"
          end
        end

        tools
      end

      # Load a single profile file
      #
      # @param file [String] the path to the YAML file
      # @return [Hash] the loaded profile
      def load_profile(file)
        content = File.read(file)
        profile = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: true)

        # Convert string keys to symbols for consistency
        profile = symbolize_keys(profile)

        # Resolve inheritance if present
        resolve_inheritance(profile, file)

        profile
      end

      # Load a specific tool by name
      #
      # @param name [String] the tool name
      # @param options [Hash] loading options
      # @option options [String] :version specific version to load
      # @option options [String] :registry_path path to registry
      # @return [Hash, nil] the tool profile or nil if not found
      def load_tool(name, options = {})
        registry_path = options[:registry_path] || @default_registry_path

        raise ProfileLoadError, "Registry path not configured" unless registry_path

        # Try version-specific directory first
        version = options[:version]
        if version
          file = File.join(registry_path, "tools", name, "#{version}.yaml")
          return load_profile(file) if File.exist?(file)
        end

        # Search in all matching files
        pattern = File.join(registry_path, "tools", name, "*.yaml")
        files = Dir.glob(pattern).sort

        if files.empty?
          # Try the old format (single file per tool)
          file = File.join(registry_path, "tools", "#{name}.yaml")
          return load_profile(file) if File.exist?(file)
          return nil
        end

        # Return the latest version if version not specified
        if version.nil?
          # Sort by version and return the newest
          sorted_files = files.sort_by { |f| Gem::Version.new(File.basename(f, ".yaml")) }
          load_profile(sorted_files.last)
        else
          # Find specific version
          version_file = files.find { |f| File.basename(f, ".yaml") == version }
          version_file ? load_profile(version_file) : nil
        end
      end

      # Set the default registry path
      #
      # @param path [String] the default registry path
      def default_registry_path=(path)
        @default_registry_path = path
      end

      # Get the default registry path
      #
      # @return [String, nil] the default registry path
      def default_registry_path
        @default_registry_path
      end

      # Get all available tool names
      #
      # @return [Array<String>] list of tool names
      def tools
        registry_path = @default_registry_path
        return [] unless registry_path

        tools_dir = File.join(registry_path, "tools")
        return [] unless Dir.exist?(tools_dir)

        # List all directories in tools/
        Dir.glob(File.join(tools_dir, "*")).select do |path|
          File.directory?(path)
        end.map do |path|
          File.basename(path)
        end.sort
      end

      # Find the newest compatible version of a tool
      #
      # @param tool_name [String] the tool name
      # @param options [Hash] search options
      # @option options [String] :platform platform (default: auto-detect)
      # @option options [String] :shell shell (default: auto-detect)
      # @option options [String] :version_constraint version constraint
      # @return [Hash, nil] the best matching profile or nil
      def find_compatible_profile(tool_name, options = {})
        profiles = load_tool_profiles(tool_name)
        return nil if profiles.nil? || profiles.empty?

        platform = options[:platform] || Platform.detect
        shell = options[:shell] || Shell.detect
        version = options[:version]

        # Filter by platform and shell
        candidates = profiles.select do |profile|
          profile_platforms = profile[:platforms] || profile[:platform]
          profile_shells = profile[:shells] || profile[:shell]

          platform_match = profile_platforms.include?(platform) if profile_platforms
          shell_match = profile_shells.include?(shell) if profile_shells

          (platform_match || profile_platforms.nil?) && (shell_match || profile_shells.nil?)
        end

        # Further filter by version if specified
        if version && !candidates.empty?
          constraint = Gem::Requirement.new(version)
          candidates.select! do |profile|
            profile_version = profile[:version]
            next true unless profile_version

            constraint.satisfied_by?(Gem::Version.new(profile_version))
          end
        end

        # Return the first matching profile (prefer newer versions)
        candidates.first
      end

      private

      # Load all profiles for a specific tool
      def load_tool_profiles(name)
        registry_path = @default_registry_path
        return nil unless registry_path

        pattern = File.join(registry_path, "tools", name, "*.yaml")
        files = Dir.glob(pattern)

        return nil if files.empty?

        files.flat_map do |file|
          begin
            profile = load_profile(file)
            profile[:_file_path] = file
            profile
          rescue => e
            warn "Warning: Failed to load profile #{file}: #{e.message}"
            []
          end
        end
      end

      # Resolve profile inheritance
      #
      # @param profile [Hash] the profile to resolve
      # @param file_path [String] the path to the profile file
      def resolve_inheritance(profile, file_path)
        return unless profile[:profiles]

        base_dir = File.dirname(file_path)

        profile[:profiles].each do |p|
          next unless p[:inherits]

          parent_profile = find_parent_profile(p[:inherits], profile[:profiles], base_dir)
          if parent_profile
            # Merge parent into child (child takes precedence)
            p.merge!(parent_profile) { |_, child_val, _| child_val }
          end
        end
      end

      # Find a parent profile within the same file
      def find_parent_profile(name, profiles, _base_dir)
        profiles.find { |p| p[:name] == name }
      end

      # Recursively convert string keys to symbols
      #
      # @param hash [Hash] the hash to convert
      # @return [Hash] the hash with symbolized keys
      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys do |key|
          key.is_a?(String) ? key.to_sym : key
        end.transform_values do |value|
          case value
          when Hash
            symbolize_keys(value)
          when Array
            value.map { |v| v.is_a?(Hash) ? symbolize_keys(v) : v }
          else
            value
          end
        end
      end
    end
  end
end
