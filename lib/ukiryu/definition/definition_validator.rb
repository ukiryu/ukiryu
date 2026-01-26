# frozen_string_literal: true

require_relative 'validation_result'
require_relative 'loader'
require 'yaml'
require 'open-uri'
require 'net/http'

module Ukiryu
  module Definition
    # Validate tool definitions against JSON Schema
    #
    # This class provides validation functionality for tool definitions
    # using JSON Schema. The json-schema gem is optional; if not available,
    # basic structural validation is performed instead.
    class DefinitionValidator
      # Default schema version
      DEFAULT_SCHEMA_VERSION = '1.0'

      # Remote schema URL
      REMOTE_SCHEMA_URL = 'https://raw.githubusercontent.com/ukiryu/schemas/refs/heads/main/v1/tool.schema.yaml'

      class << self
        # Check if JSON Schema validation is available
        #
        # @return [Boolean] true if json-schema gem is available
        def schema_validation_available?
          return @schema_validation_available if defined?(@schema_validation_available)

          @schema_validation_available = begin
            require 'json-schema'
            true
          rescue LoadError
            false
          end
        end

        # Find schema file
        #
        # @param version [String] schema version
        # @return [String, nil] path to schema file from UKIRYU_SCHEMA_PATH env var, or nil
        def find_schema(_version = DEFAULT_SCHEMA_VERSION)
          # Only check environment variable for local schema path
          schema_path = ENV['UKIRYU_SCHEMA_PATH']
          return schema_path if schema_path && File.exist?(schema_path)

          nil
        end

        # Load schema
        #
        # @param schema_path [String] path to schema file
        # @return [Hash, nil] parsed schema, or nil if not available
        def load_schema(schema_path)
          return nil unless schema_path && File.exist?(schema_path)

          case File.extname(schema_path)
          when '.json'
            JSON.parse(File.read(schema_path))
          when '.yaml', '.yml'
            YAML.safe_load(File.read(schema_path), permitted_classes: [Symbol])
          end
        rescue JSON::ParserError, Psych::SyntaxError, Errno::ENOENT
          nil
        end

        # Validate a definition hash
        #
        # @param definition [Hash] the definition to validate
        # @param schema_path [String, nil] optional schema path
        # @return [ValidationResult] validation result
        def validate(definition, schema_path: nil)
          errors = []
          warnings = []

          # Basic structural validation (always available)
          structural_result = validate_structure(definition)
          errors.concat(structural_result[:errors])
          warnings.concat(structural_result[:warnings])

          # JSON Schema validation (if available)
          if schema_validation_available?
            schema = schema_path ? load_schema(schema_path) : find_and_load_schema
            if schema
              schema_result = validate_against_schema(definition, schema)
              errors.concat(schema_result[:errors])
              warnings.concat(schema_result[:warnings])
            end
            # If schema file not found, silently skip JSON schema validation
            # Structural validation is sufficient
          else
            warnings << 'json-schema gem not available, only structural validation performed'
          end

          if errors.empty?
            warnings.empty? ? ValidationResult.success : ValidationResult.with_warnings(warnings)
          else
            ValidationResult.failure(errors, warnings)
          end
        end

        # Validate a definition file
        #
        # @param file_path [String] path to definition file
        # @param schema_path [String, nil] optional schema path
        # @return [ValidationResult] validation result
        def validate_file(file_path, schema_path: nil)
          # Load raw YAML hash for validation
          definition = YAML.safe_load(File.read(file_path), permitted_classes: [Symbol, Date, Time])
          validate(definition, schema_path: schema_path)
        rescue Ukiryu::DefinitionNotFoundError
          ValidationResult.failure(["File not found: #{file_path}"])
        rescue Ukiryu::DefinitionLoadError, Ukiryu::DefinitionValidationError => e
          ValidationResult.failure([e.message])
        rescue Errno::ENOENT
          ValidationResult.failure(["File not found: #{file_path}"])
        rescue Psych::SyntaxError => e
          ValidationResult.failure(["Invalid YAML: #{e.message}"])
        end

        # Validate a YAML string
        #
        # @param yaml_string [String] YAML content
        # @param schema_path [String, nil] optional schema path
        # @return [ValidationResult] validation result
        def validate_string(yaml_string, schema_path: nil)
          definition = YAML.safe_load(yaml_string, permitted_classes: [Symbol, Date, Time])
          validate(definition, schema_path: schema_path)
        rescue Psych::SyntaxError => e
          ValidationResult.failure(["Invalid YAML: #{e.message}"])
        end

        private

        # Find and load schema
        #
        # @return [Hash, nil] schema hash or nil
        def find_and_load_schema
          # Try local schema first
          schema_path = find_schema
          schema = load_schema(schema_path) if schema_path
          return schema if schema

          # Fallback to remote schema
          download_and_load_schema
        end

        # Download schema from remote URL
        #
        # @return [Hash, nil] schema hash or nil
        def download_and_load_schema
          YAML.safe_load(URI.open(REMOTE_SCHEMA_URL).read, permitted_classes: [Symbol])
        rescue OpenURI::HTTPError, SocketError, Timeout::Error, Psych::SyntaxError
          nil
        end

        # Validate basic structure
        #
        # @param definition [Hash] the definition
        # @return [Hash] errors and warnings
        def validate_structure(definition)
          errors = []
          warnings = []

          # Check if definition is a hash
          return { errors: ['Definition must be a hash/object'], warnings: [] } unless definition.is_a?(Hash)

          # Check name format (NOT validated by schema)
          name = definition[:name] || definition['name']
          if name
            name_str = name.to_s
            errors << 'Tool name must not contain whitespace' if name_str =~ /\s/
            warnings << 'Tool name starting with number may cause issues' if name_str =~ /^[0-9]/
            warnings << 'Tool name should contain only lowercase letters, numbers, hyphens, and underscores' if name_str !~ /^[a-z0-9_-]+$/
          end

          # Check schema version format (NOT validated by schema)
          has_schema_version = definition.key?(:ukiryu_schema) || definition.key?('ukiryu_schema')
          if has_schema_version
            schema_version = definition[:ukiryu_schema] || definition['ukiryu_schema']
            schema_version_str = schema_version.to_s
            warnings << "Invalid schema version format: #{schema_version} (expected format: '1.0')" unless schema_version_str =~ /^\d+\.\d+$/
          end

          { errors: errors, warnings: warnings }
        end

        # Validate a profile
        #
        # @param profile [Hash] the profile
        # @param index [Integer] profile index
        # @return [Hash] errors and warnings
        def validate_profile(profile, index)
          errors = []
          warnings = []

          return { errors: ["Profile #{index} must be a hash/object"], warnings: [] } unless profile.is_a?(Hash)

          # All profile structural validation is already done by JSON Schema
          # (required fields, types, enum values, etc.)

          { errors: errors, warnings: warnings }
        end

        # Validate against JSON Schema
        #
        # @param definition [Hash] the definition
        # @param schema [Hash] JSON Schema
        # @return [Hash] errors and warnings
        def validate_against_schema(definition, schema)
          errors = []
          warnings = []

          begin
            # Convert symbol keys to strings for JSON Schema validation
            stringified = stringify_keys(definition)

            validation = JSON::Validator.fully_validate(schema, stringified, errors_as_objects: true)

            validation.each do |error|
              if error[:type] == 'unknown'
                warnings << error[:message]
              else
                errors << "#{error[:message]} (at #{error[:fragment]})"
              end
            end
          rescue JSON::Schema::ValidationError => e
            errors << "Schema validation error: #{e.message}"
          end

          { errors: errors, warnings: warnings }
        end

        # Convert symbol keys to strings
        #
        # @param hash [Hash] the hash
        # @return [Hash] hash with string keys
        def stringify_keys(hash)
          return hash unless hash.is_a?(Hash)

          hash.transform_keys(&:to_s).transform_values do |v|
            case v
            when Hash
              stringify_keys(v)
            when Array
              v.map { |item| item.is_a?(Hash) ? stringify_keys(item) : item }
            else
              v
            end
          end
        end
      end
    end
  end
end
