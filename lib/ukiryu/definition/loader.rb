# frozen_string_literal: true

module Ukiryu
  module Definition
    # Loader for tool definitions from various sources
    #
    # The loader orchestrates loading tool definitions from different
    # sources (files, strings, bundled locations, register) and provides
    # a unified interface for definition loading.
    class Loader
      class << self
        # Load a tool definition from a source
        #
        # @param source [Source] the definition source
        # @param options [Hash] loading options
        # @option options [Symbol] :validation validation mode (:strict, :lenient, :none)
        # @return [Models::ToolDefinition] the loaded tool definition
        # @raise [DefinitionLoadError] if loading fails
        def load_from_source(source, options = {})
          # Check cache first
          cache_key = source.cache_key
          return profile_cache[cache_key] if profile_cache.key?(cache_key)

          # Load YAML content from source
          yaml_content = source.load

          # Parse using lutaml-model
          profile = parse_yaml(yaml_content, source)

          # Validate if requested
          validation_mode = options[:validation] || :strict
          validate_profile(profile, validation_mode) if validation_mode != :none

          # Resolve profile inheritance (merges parent commands into child profiles)
          profile.resolve_inheritance!

          # Cache the profile
          profile_cache[cache_key] = profile

          profile
        end

        # Load a tool definition from a file path
        #
        # @param path [String] path to the definition file
        # @param options [Hash] loading options
        # @return [Models::ToolDefinition] the loaded tool definition
        def load_from_file(path, options = {})
          source = Sources::FileSource.new(path)
          load_from_source(source, options)
        end

        # Load a tool definition from a YAML string
        #
        # @param yaml_string [String] the YAML content
        # @param options [Hash] loading options
        # @return [Models::ToolDefinition] the loaded tool definition
        def load_from_string(yaml_string, options = {})
          source = Sources::StringSource.new(yaml_string)
          load_from_source(source, options)
        end

        # Get the profile cache
        #
        # @return [Hash] the profile cache
        def profile_cache
          @profile_cache ||= {}
        end

        # Clear the profile cache
        #
        # @param source [Source, nil] clear specific source or all if nil
        def clear_cache(source = nil)
          if source
            profile_cache.delete(source.cache_key)
          else
            profile_cache.clear
          end
        end

        private

        # Parse YAML content into a tool definition
        #
        # @param yaml_content [String] the YAML content
        # @param source [Source] the source for error messages
        # @return [Models::ToolDefinition] the parsed profile
        # @raise [DefinitionLoadError] if parsing fails
        def parse_yaml(yaml_content, source)
          Models::ToolDefinition.from_yaml(yaml_content)
        rescue Psych::SyntaxError => e
          raise Ukiryu::Errors::DefinitionLoadError,
                "Invalid YAML in #{source}: #{e.message}"
        rescue Lutaml::Model::InvalidFormatError => e
          raise Ukiryu::Errors::DefinitionLoadError,
                "Invalid YAML format in #{source}: #{e.message}"
        rescue StandardError => e
          raise Ukiryu::Errors::DefinitionLoadError,
                "Failed to parse definition from #{source}: #{e.message}"
        end

        # Validate a tool profile
        #
        # @param profile [Models::ToolDefinition] the profile to validate
        # @param mode [Symbol] validation mode (:strict, :lenient)
        # @raise [DefinitionValidationError] if validation fails in strict mode
        def validate_profile(profile, mode)
          errors = []

          # Check required fields
          errors << "Missing 'name' field" unless profile.name
          errors << "Missing 'version' field" unless profile.version
          errors << "Missing 'profiles' field or profiles is empty" unless profile.profiles&.any?

          # Check ukiryu_schema format if present
          errors << "Invalid ukiryu_schema format: #{profile.ukiryu_schema}" if profile.ukiryu_schema && !profile.ukiryu_schema.match?(/^\d+\.\d+$/)

          # Check $self URI format if present
          errors << "Invalid $self URI format: #{profile.self_uri}" if profile.self_uri && !valid_uri?(profile.self_uri) && (mode == :strict)

          return if errors.empty?

          message = "Profile validation failed:\n  - #{errors.join("\n  - ")}"
          raise Ukiryu::Errors::DefinitionValidationError, message if mode == :strict

          warn "[Ukiryu] #{message}"
        end

        # Check if a string is a valid URI
        #
        # @param uri_string [String] the URI to check
        # @return [Boolean] true if valid URI
        def valid_uri?(uri_string)
          uri_string =~ %r{^https?://} || uri_string =~ %r{^file://} ? true : false
        end
      end
    end
  end
end
