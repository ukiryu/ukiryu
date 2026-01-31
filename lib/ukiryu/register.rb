# frozen_string_literal: true

require 'yaml'
require_relative 'utils'
require_relative 'models/interface'
require_relative 'models/implementation_index'
require_relative 'models/implementation_version'
require_relative 'register_auto_manager'

module Ukiryu
  # YAML profile register loader
  #
  # Provides access to tool definitions from YAML profiles in a register directory.
  # Supports lazy loading: metadata can be loaded without full profile parsing.
  #
  # Features:
  # - Cached version listings to avoid repeated glob operations
  # - Automatic cache invalidation when register path changes
  # - Automatic register cloning to ~/.ukiryu/register if not configured
  class Register
    class << self
      # Set the default register path
      #
      # @param path [String] the default register path

      # Get the default register path
      #
      # @return [String, nil] the default register path
      attr_accessor :default_register_path

      # Reset the version cache (mainly for testing)
      def reset_version_cache
        @version_cache = nil
        @register_cache_key = nil
      end

      # Get all available tool names
      # Only returns tools that have an index.yaml (new architecture)
      #
      # @return [Array<String>] list of tool names
      def tools
        register_path = effective_register_path
        return [] unless register_path

        tools_dir = File.join(register_path, 'tools')
        return [] unless Dir.exist?(tools_dir)

        # List all directories that have an index.yaml file
        Dir.glob(File.join(tools_dir, '*', 'index.yaml')).map do |index_file|
          File.basename(File.dirname(index_file))
        end.sort
      end

      # Get available versions for a tool (cached) - DEPRECATED, kept for compatibility
      #
      # @param name [String, Symbol] the tool name
      # @param register_path [String, nil] the register path
      # @return [Hash] mapping of version filename to version string
      def list_versions(name, register_path: nil)
        register_path ||= effective_register_path
        return {} unless register_path

        # For new architecture, load the index and get versions
        index = load_implementation_index(name, register_path: register_path)
        return {} unless index

        # Extract versions from all implementations
        # Return a hash mapping version strings to full file paths
        versions = {}
        index.implementations.each do |impl|
          impl_name = impl[:name] || impl['name']
          impl_versions = impl[:versions] || impl['versions']
          next unless impl_versions

          impl_versions.each do |version_spec|
            equals = version_spec[:equals] || version_spec['equals']
            file = version_spec[:file] || version_spec['file']
            next unless equals && file

            # Build full path: tools/tool_name/implementation_name/file.yaml
            full_path = File.join(register_path, 'tools', name.to_s, impl_name.to_s, file)
            versions[full_path] = equals
          end
        end

        versions
      end

      # Load tool metadata only (lightweight, without full parsing)
      # This is much faster than loading the full definition when only metadata is needed
      #
      # Supports both exact name lookup and interface-based discovery
      #
      # @param name [String, Symbol] the tool name or interface name
      # @param options [Hash] loading options
      # @option options [String] :version specific version to load
      # @option options [String] :register_path path to register
      # @return [ToolMetadata, nil] the tool metadata or nil if not found
      def load_tool_metadata(name, options = {})
        register_path = options[:register_path] || effective_register_path

        # First try exact name match
        yaml_content = load_tool_yaml(name, options.merge(register_path: register_path))
        if yaml_content
          hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
          return ToolMetadata.from_hash(hash, tool_name: name.to_s, register_path: register_path) if hash
        end

        # If not found, try interface-based discovery using ToolIndex
        index = Ukiryu::ToolIndex.instance

        # Try exact interface name first
        result = index.find_by_interface(name.to_sym)
        return result if result

        # Try interface name with common version suffix (e.g., imagemagick/1.0)
        # This handles tools where the interface is defined with version suffix
        name_str = name.to_s
        [:"#{name_str}/1.0", :"#{name_str}/1", :"v#{name_str}/1.0"].each do |versioned_interface|
          result = index.find_by_interface(versioned_interface)
          return result if result
        end

        nil
      end

      # Load tool YAML file content (for lutaml-model parsing)
      #
      # @param name [String, Symbol] the tool name
      # @param options [Hash] loading options
      # @option options [String] :version specific version to load
      # @option options [String] :register_path path to register
      # @return [String, nil] the YAML content or nil if not found
      def load_tool_yaml(name, options = {})
        register_path = options[:register_path] || effective_register_path

        return nil unless register_path

        # Convert to string for path operations
        name_str = name.to_s

        # Try version-specific directory first
        version = options[:version]
        if version
          file = File.join(register_path, 'tools', name_str, "#{version}.yaml")
          return File.read(file) if File.exist?(file)
        end

        # Use cached version list if available
        versions = list_versions(name_str, register_path: register_path)

        if versions.empty?
          # Try the old format (single file per tool)
          file = File.join(register_path, 'tools', "#{name_str}.yaml")
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
      # @option options [String] :register_path path to register
      # @option options [String] :schema_path path to schema file
      # @return [ValidationResult] the validation result
      def validate_tool(name, options = {})
        yaml_content = load_tool_yaml(name, options)
        return Models::ValidationResult.not_found(name.to_s) unless yaml_content

        profile = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
        return Models::ValidationResult.invalid(name.to_s, ['Failed to parse YAML']) unless profile

        errors = Ukiryu::SchemaValidator.validate_profile(profile, options)
        if errors.empty?
          Models::ValidationResult.valid(name.to_s)
        else
          Models::ValidationResult.invalid(name.to_s, errors)
        end
      end

      # Validate all tool profiles in the register
      #
      # @param options [Hash] validation options
      # @option options [String] :register_path path to register
      # @option options [String] :schema_path path to schema file
      # @return [Array<ValidationResult>] list of validation results
      def validate_all_tools(options = {})
        tools.map do |tool_name|
          validate_tool(tool_name, options)
        end
      end

      # Load an Interface by path (e.g., "gzip/1.0")
      #
      # @param path [String] the interface path (e.g., "gzip/1.0")
      # @param options [Hash] loading options
      # @option options [String] :register_path path to register
      # @return [Models::Interface, nil] the interface or nil if not found
      def load_interface(path, options = {})
        register_path = options[:register_path] || effective_register_path
        return nil unless register_path

        file = File.join(register_path, 'interfaces', "#{path}.yaml")
        return nil unless File.exist?(file)

        yaml_content = File.read(file)
        hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
        return nil unless hash

        Models::Interface.from_hash(symbolize_keys(hash))
      end

      # Load an ImplementationIndex by tool name
      #
      # @param tool_name [String, Symbol] the tool name
      # @param options [Hash] loading options
      # @option options [String] :register_path path to register
      # @return [Models::ImplementationIndex, nil] the index or nil if not found
      def load_implementation_index(tool_name, options = {})
        register_path = options[:register_path] || effective_register_path

        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG Register.load_implementation_index] tool_name=#{tool_name}"
          warn "[UKIRYU DEBUG] register_path = #{register_path.inspect}"
        end

        return nil unless register_path

        file = File.join(register_path, 'tools', tool_name.to_s, 'index.yaml')
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG] index file = #{file.inspect}"
          warn "[UKIRYU DEBUG] File exists? #{File.exist?(file)}"
        end
        return nil unless File.exist?(file)

        yaml_content = File.read(file)
        hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
        return nil unless hash

        # Symbolize string keys recursively
        symbolized_hash = symbolize_keys(hash)
        Models::ImplementationIndex.from_hash(symbolized_hash)
      end

      # Load an ImplementationVersion by tool, implementation, and file path
      #
      # @param tool_name [String, Symbol] the tool name
      # @param implementation_name [String, Symbol] the implementation name (e.g., "gnu")
      # @param file_path [String] the file path relative to implementation directory
      # @param options [Hash] loading options
      # @option options [String] :register_path path to register
      # @return [Models::ImplementationVersion, nil] the implementation version or nil if not found
      def load_implementation_version(tool_name, implementation_name, file_path, options = {})
        register_path = options[:register_path] || effective_register_path

        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG Register.load_implementation_version] tool=#{tool_name}, impl=#{implementation_name}, file=#{file_path}"
          warn "[UKIRYU DEBUG] register_path = #{register_path.inspect}"
        end

        return nil unless register_path

        file = File.join(register_path, 'tools', tool_name.to_s, implementation_name.to_s, file_path)
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG] Loading from file: #{file.inspect}"
          warn "[UKIRYU DEBUG] File exists? #{File.exist?(file)}"
        end
        return nil unless File.exist?(file)

        yaml_content = File.read(file)
        hash = YAML.safe_load(yaml_content, permitted_classes: [Symbol], aliases: true)
        return nil unless hash

        Models::ImplementationVersion.from_hash(symbolize_keys(hash))
      end

      private

      # Get the effective register path
      #
      # Returns the manually set path if available, otherwise uses
      # RegisterAutoManager to get or create the default path.
      #
      # @return [String, nil] the register path, or nil if unavailable
      def effective_register_path
        # If manually set, use that
        return @default_register_path if @default_register_path

        # Otherwise, use RegisterAutoManager (auto-clone if needed)
        # Use :: to reference top-level Ukiryu namespace
        auto_path = ::Ukiryu::RegisterAutoManager.register_path
        warn "[UKIRYU DEBUG] Using RegisterAutoManager path: #{auto_path.inspect}" if ENV['UKIRYU_DEBUG_EXECUTABLE']
        auto_path
      end

      # Recursively symbolize hash keys
      #
      # @param hash [Hash] the hash to symbolize
      # @return [Hash] hash with symbolized keys
      def symbolize_keys(hash)
        Utils.symbolize_keys(hash)
      end

      # Scan tool versions and sort by Gem::Version
      #
      # @param name [String] the tool name
      # @param register_path [String] the register path
      # @return [Hash] mapping of version filename to Gem::Version
      def scan_tool_versions(name, register_path)
        pattern = File.join(register_path, 'tools', name.to_s, '*.yaml')
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
