# frozen_string_literal: true

require 'yaml'
require_relative 'models/tool_metadata'
require_relative 'models/validation_result'
require_relative 'tool_index'
require_relative 'schema_validator'

module Ukiryu
  # YAML profile registry loader
  #
  # Provides access to tool definitions from YAML profiles in a registry directory.
  # Supports lazy loading: metadata can be loaded without full profile parsing.
  #
  # Features:
  # - Cached version listings to avoid repeated glob operations
  # - Automatic cache invalidation when registry path changes
  class Registry
    class << self
      # Set the default registry path
      #
      # @param path [String] the default registry path

      # Get the default registry path
      #
      # @return [String, nil] the default registry path
      attr_accessor :default_registry_path

      # Reset the version cache (mainly for testing)
      def reset_version_cache
        @version_cache = nil
        @registry_cache_key = nil
      end

      # Get all available tool names
      #
      # @return [Array<String>] list of tool names
      def tools
        registry_path = @default_registry_path
        return [] unless registry_path

        tools_dir = File.join(registry_path, 'tools')
        return [] unless Dir.exist?(tools_dir)

        # List all directories in tools/
        Dir.glob(File.join(tools_dir, '*')).select do |path|
          File.directory?(path)
        end.map do |path|
          File.basename(path)
        end.sort
      end

      # Get available versions for a tool (cached)
      #
      # @param name [String, Symbol] the tool name
      # @param registry_path [String, nil] the registry path
      # @return [Hash] mapping of version filename to Gem::Version
      def list_versions(name, registry_path: nil)
        registry_path ||= @default_registry_path
        return {} unless registry_path

        # Initialize cache
        @version_cache ||= {}
        @registry_cache_key ||= registry_path

        # Clear cache if registry path changed
        if @registry_cache_key != registry_path
          @version_cache.clear
          @registry_cache_key = registry_path
        end

        # Check cache
        cache_key = name.to_sym
        return @version_cache[cache_key].dup if @version_cache[cache_key]

        # Build version list
        versions = scan_tool_versions(name, registry_path)
        @version_cache[cache_key] = versions

        versions.dup
      end

      # Load tool metadata only (lightweight, without full parsing)
      # This is much faster than loading the full definition when only metadata is needed
      #
      # Supports both exact name lookup and interface-based discovery
      #
      # @param name [String, Symbol] the tool name or interface name
      # @param options [Hash] loading options
      # @option options [String] :version specific version to load
      # @option options [String] :registry_path path to registry
      # @return [ToolMetadata, nil] the tool metadata or nil if not found
      def load_tool_metadata(name, options = {})
        registry_path = options[:registry_path] || @default_registry_path

        # First try exact name match
        yaml_content = load_tool_yaml(name, options.merge(registry_path: registry_path))
        if yaml_content
          hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol])
          return ToolMetadata.from_hash(hash, tool_name: name.to_s, registry_path: registry_path) if hash
        end

        # If not found, try interface-based discovery using ToolIndex
        index = ToolIndex.instance
        index.find_by_interface(name.to_sym)
      end

      # Load tool YAML file content (for lutaml-model parsing)
      #
      # @param name [String, Symbol] the tool name
      # @param options [Hash] loading options
      # @option options [String] :version specific version to load
      # @option options [String] :registry_path path to registry
      # @return [String, nil] the YAML content or nil if not found
      def load_tool_yaml(name, options = {})
        registry_path = options[:registry_path] || @default_registry_path

        return nil unless registry_path

        # Convert to string for path operations
        name_str = name.to_s

        # Try version-specific directory first
        version = options[:version]
        if version
          file = File.join(registry_path, 'tools', name_str, "#{version}.yaml")
          return File.read(file) if File.exist?(file)
        end

        # Use cached version list if available
        versions = list_versions(name_str, registry_path: registry_path)

        if versions.empty?
          # Try the old format (single file per tool)
          file = File.join(registry_path, 'tools', "#{name_str}.yaml")
          return File.read(file) if File.exist?(file)

          return nil
        end

        # Return specific version if requested
        if version
          version_file = versions.keys.find { |f| File.basename(f, '.yaml') == version }
          return version_file ? File.read(version_file) : nil
        end

        # Return the latest version (already sorted from scan_tool_versions)
        File.read(versions.keys.last)
      end

      # Validate a tool profile against the schema
      #
      # @param name [String, Symbol] the tool name
      # @param options [Hash] validation options
      # @option options [String] :version specific version to validate
      # @option options [String] :registry_path path to registry
      # @option options [String] :schema_path path to schema file
      # @return [ValidationResult] the validation result
      def validate_tool(name, options = {})
        yaml_content = load_tool_yaml(name, options)
        return Models::ValidationResult.not_found(name.to_s) unless yaml_content

        profile = YAML.safe_load(yaml_content, permitted_classes: [Symbol])
        return Models::ValidationResult.invalid(name.to_s, ['Failed to parse YAML']) unless profile

        errors = SchemaValidator.validate_profile(profile, options)
        if errors.empty?
          Models::ValidationResult.valid(name.to_s)
        else
          Models::ValidationResult.invalid(name.to_s, errors)
        end
      end

      # Validate all tool profiles in the registry
      #
      # @param options [Hash] validation options
      # @option options [String] :registry_path path to registry
      # @option options [String] :schema_path path to schema file
      # @return [Array<ValidationResult>] list of validation results
      def validate_all_tools(options = {})
        tools.map do |tool_name|
          validate_tool(tool_name, options)
        end
      end

      private

      # Scan tool versions and sort by Gem::Version
      #
      # @param name [String] the tool name
      # @param registry_path [String] the registry path
      # @return [Hash] mapping of version filename to Gem::Version
      def scan_tool_versions(name, registry_path)
        pattern = File.join(registry_path, 'tools', name.to_s, '*.yaml')
        files = Dir.glob(pattern)

        # Sort files by Gem::Version for proper version ordering
        files.sort_by { |f| Gem::Version.new(File.basename(f, '.yaml')) }
             .each_with_object({}) { |file, hash| hash[file] = Gem::Version.new(File.basename(file, '.yaml')) }
      rescue ArgumentError
        # If version parsing fails, return unsorted files
        files.each_with_object({}) { |file, hash| hash[file] = File.basename(file, '.yaml') }
      end
    end
  end
end
