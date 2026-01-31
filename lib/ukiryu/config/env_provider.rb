# frozen_string_literal: true

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
          Ukiryu::Config::EnvSchema.all_attributes.each do |attr|
            env_key = Ukiryu::Config::EnvSchema.env_key(attr)
            value = ENV[env_key]

            # Convert and store if value exists
            result[attr] = Ukiryu::Config::TypeConverter.convert(attr, value) if value
          end

          # Handle NO_COLOR standard environment variable (https://no-color.org/)
          # NO_COLOR takes precedence over UKIRYU_USE_COLOR
          # When set (to any value), colors are disabled
          result[:use_color] = false if ENV['NO_COLOR']

          result
        end

        # Load execution-specific environment overrides
        def load_execution
          load_attributes(Ukiryu::Config::EnvSchema.all_execution_attributes)
        end

        # Load output-specific environment overrides
        def load_output
          load_attributes(Ukiryu::Config::EnvSchema.all_output_attributes)
        end

        # Load register-specific environment overrides
        def load_register
          load_attributes(Ukiryu::Config::EnvSchema.all_register_attributes)
        end

        private

        def load_attributes(attributes)
          result = {}
          attributes.each do |attr|
            env_key = Ukiryu::Config::EnvSchema.env_key(attr)
            value = ENV[env_key]

            # Convert and store if value exists
            result[attr] = Ukiryu::Config::TypeConverter.convert(attr, value) if value
          end
          result
        end
      end
    end
  end
end
