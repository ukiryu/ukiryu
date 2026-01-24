# frozen_string_literal: true

module Ukiryu
  class Config
    # Schema definition for configuration attributes
    # Defines attribute types and ENV variable mappings
    class EnvSchema
      ATTRIBUTE_TYPES = {
        # Execution options
        timeout: :integer,
        debug: :boolean,
        dry_run: :boolean,
        metrics: :boolean,
        shell: :symbol,

        # Output options
        format: :symbol,
        output: :string,

        # Register options
        register: :string,

        # Tool discovery options
        search_paths: :string, # Comma-separated paths

        # Color options
        use_color: :boolean
      }.freeze

      class << self
        def type_for(attribute)
          ATTRIBUTE_TYPES[attribute.to_sym]
        end

        # Generate ENV key for a config attribute
        # e.g., env_key(:timeout) => "UKIRYU_TIMEOUT"
        def env_key(attribute)
          "UKIRYU_#{attribute.to_s.upcase}"
        end

        # All execution attributes
        def all_execution_attributes
          %i[timeout debug dry_run metrics shell]
        end

        # All output attributes
        def all_output_attributes
          %i[format output use_color]
        end

        # All register attributes
        def all_register_attributes
          %i[register search_paths]
        end

        # All attributes
        def all_attributes
          %i[timeout debug dry_run metrics shell format output register search_paths use_color]
        end
      end
    end
  end
end
