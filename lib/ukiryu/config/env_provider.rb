# frozen_string_literal: true

require_relative 'env_schema'
require_relative 'type_converter'

module Ukiryu
  class Config
    # Provides environment variable values for configuration
    # Reads and parses UKIRYU_* environment variables and standard env vars like NO_COLOR
    class EnvProvider
      class << self
        # Load all environment overrides
        def load_all
          result = {}

          # Load UKIRYU_* environment variables
          EnvSchema.all_attributes.each do |attr|
            env_key = EnvSchema.env_key(attr)
            value = ENV[env_key]

            # Convert and store if value exists
            result[attr] = TypeConverter.convert(attr, value) if value
          end

          # Handle NO_COLOR standard environment variable (https://no-color.org/)
          # NO_COLOR takes precedence over UKIRYU_USE_COLOR
          # When set (to any value), colors are disabled
          result[:use_color] = false if ENV['NO_COLOR']

          result
        end

        # Load execution-specific environment overrides
        def load_execution
          load_attributes(EnvSchema.all_execution_attributes)
        end

        # Load output-specific environment overrides
        def load_output
          load_attributes(EnvSchema.all_output_attributes)
        end

        # Load registry-specific environment overrides
        def load_registry
          load_attributes(EnvSchema.all_registry_attributes)
        end

        private

        def load_attributes(attributes)
          result = {}
          attributes.each do |attr|
            env_key = EnvSchema.env_key(attr)
            value = ENV[env_key]

            # Convert and store if value exists
            result[attr] = TypeConverter.convert(attr, value) if value
          end
          result
        end
      end
    end
  end
end
