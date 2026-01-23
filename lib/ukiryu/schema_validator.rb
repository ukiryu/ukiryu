# frozen_string_literal: true

require 'json'
begin
  require 'json-schema'
rescue LoadError
  # json-schema is optional - only needed for schema validation
end
require 'yaml'

module Ukiryu
  # Schema validator for YAML tool profiles
  #
  # Validates tool profile YAML files against JSON Schema definitions.
  class SchemaValidator
    class << self
      # Validate a tool profile against the schema
      #
      # @param profile [Hash] the loaded profile hash
      # @param options [Hash] validation options
      # @option options [String] :schema_path path to schema file
      # @option options [Boolean] :strict whether to use strict validation
      # @return [Array<String>] list of validation errors (empty if valid)
      def validate_profile(profile, options = {})
        # Check if json-schema gem is available
        return ["json-schema gem not installed. Add 'json-schema' to Gemfile for schema validation."] unless defined?(JSON::Validator)

        errors = []

        # Load the schema
        schema = load_schema(options[:schema_path])
        return ['Failed to load schema'] unless schema

        # Validate against JSON schema
        begin
          # JSON Schema library expects the data to be a hash
          validation_errors = JSON::Validator.fully_validate(schema, profile, strict: options[:strict] || false)

          # Convert errors to readable format
          validation_errors.each do |error|
            errors << format_schema_error(error)
          end
        rescue JSON::Schema::ValidationError => e
          errors << "Schema validation error: #{e.message}"
        end

        errors
      end

      # Load and parse the JSON schema
      #
      # @param path [String, nil] path to schema file (optional)
      # @return [Hash] the parsed schema
      def load_schema(path = nil)
        schema_path = path || default_schema_path
        return nil unless schema_path && File.exist?(schema_path)

        schema_content = File.read(schema_path)
        parsed = YAML.safe_load(schema_content)

        # Convert YAML schema to JSON schema format
        # YAML schema uses $schema, definitions, etc.
        convert_yaml_schema_to_json(parsed)
      end

      # Get the default schema path
      #
      # @return [String, nil] the default schema path
      def default_schema_path
        # Schema is in the sibling 'schema' directory at the same level as the gem
        # From lib/ukiryu/, we go up to gem root, then to sibling schema/
        gem_root = File.expand_path('../..', __dir__) # ukiryu gem root
        schema_dir = File.expand_path('../schema', gem_root) # src/ukiryu/schema/
        schema_file = File.join(schema_dir, 'tool-profile.schema.yaml')
        return schema_file if File.exist?(schema_file)

        nil
      end

      private

      # Convert YAML schema format to JSON schema format
      #
      # @param yaml_schema [Hash] the parsed YAML schema
      # @return [Hash] the converted JSON schema
      def convert_yaml_schema_to_json(yaml_schema)
        # The YAML schema format is very similar to JSON schema
        # Just need to ensure it has the right structure
        yaml_schema
      end

      # Format a schema error for readability
      #
      # @param error [String] the raw error message
      # @return [String] the formatted error
      def format_schema_error(error)
        error
      end
    end
  end
end
