# frozen_string_literal: true

require_relative '../models/tool_definition'
require_relative '../cache'

module Ukiryu
  module Tools
    # Generator module for dynamically creating tool-specific classes
    #
    # This module is responsible for:
    # - Loading tool definitions from YAML as lutaml-model models
    # - Generating tool classes (e.g., Ukiryu::Tools::Imagemagick)
    # - Caching generated classes with bounded LRU cache
    # - Providing constant autoloading via const_missing
    #
    module Generator
      class << self
        # Get the generated classes cache (bounded LRU cache)
        #
        # @return [Cache] the generated classes cache
        def generated_classes_cache
          @generated_classes_cache ||= Cache.new(max_size: 50, ttl: 3600)
        end

        # Get or generate a tool class
        #
        # @param tool_name [Symbol, String] the tool name
        # @return [Class] the tool class
        def generate(tool_name)
          tool_name = tool_name.to_sym
          cached = generated_classes_cache[tool_name]
          return cached if cached

          # Load the tool definition as a lutaml-model
          tool_definition = load_tool_definition(tool_name)
          raise Ukiryu::ToolNotFoundError, "Tool not found: #{tool_name}" unless tool_definition

          # Get the compatible platform profile
          platform_profile = tool_definition.compatible_profile

          # Generate the tool class
          tool_class = generate_tool_class(tool_name, tool_definition, platform_profile)

          generated_classes_cache[tool_name] = tool_class
          tool_class
        end

        # Load a ToolDefinition model from the registry
        #
        # @param tool_name [Symbol] the tool name
        # @return [Models::ToolDefinition, nil] the tool definition model
        def load_tool_definition(tool_name)
          require_relative '../registry'

          # Load the YAML file content
          yaml_content = Registry.load_tool_yaml(tool_name)
          return nil unless yaml_content

          # Use lutaml-model's from_yaml to parse
          tool_definition = Models::ToolDefinition.from_yaml(yaml_content)

          # Resolve profile inheritance (e.g., windows profiles inherit from unix)
          tool_definition&.resolve_inheritance!

          tool_definition
        end

        # Generate a tool class from a tool definition
        #
        # @param tool_name [Symbol] the tool name
        # @param tool_definition [Models::ToolDefinition] the tool definition
        # @param platform_profile [Models::PlatformProfile] the compatible platform profile
        # @return [Class] the generated tool class
        def generate_tool_class(tool_name, tool_definition, platform_profile)
          Class.new(::Ukiryu::Tools::Base) do
            @tool_name = tool_name
            @tool_definition = tool_definition
            @platform_profile = platform_profile

            # Define class methods
            singleton_class.send(:define_method, :tool_name) do
              @tool_name
            end

            singleton_class.send(:define_method, :tool_definition) do
              @tool_definition
            end

            singleton_class.send(:define_method, :platform_profile) do
              @platform_profile
            end
          end
        end

        # Generate a tool class and const it in the Tools namespace
        #
        # @param tool_name [Symbol] the tool name
        # @return [Class] the tool class
        def generate_and_const_set(tool_name)
          tool_class = generate(tool_name)
          class_name = tool_name.to_s.capitalize

          # Const the class in the Tools module
          Ukiryu::Tools.const_set(class_name, tool_class) unless Ukiryu::Tools.const_defined?(class_name)

          tool_class
        end

        # Clear the cache of generated classes
        #
        # Useful for testing or reloading profiles
        def clear_cache
          generated_classes_cache.clear
        end

        # Check if a tool class has been generated
        #
        # @param tool_name [Symbol] the tool name
        # @return [Boolean] true if the class has been generated
        def generated?(tool_name)
          generated_classes_cache.key?(tool_name.to_sym)
        end

        # Get all generated tool classes
        #
        # @return [Hash] map of tool name to class
        def all_generated
          result = {}
          generated_classes_cache.each_key do |key|
            result[key] = generated_classes_cache[key]
          end
          result
        end

        # Get a list of all available tool names
        #
        # @return [Array<Symbol>] list of tool names
        def available_tools
          require_relative '../registry'

          registry_path = Registry.default_registry_path
          return [] unless registry_path

          tools_dir = File.join(registry_path, 'tools')
          return [] unless Dir.exist?(tools_dir)

          Dir.entries(tools_dir)
             .reject { |e| e.start_with?('.') }
             .map(&:to_sym)
        end
      end
    end
  end
end
