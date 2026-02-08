# frozen_string_literal: true

module Ukiryu
  module OptionsBuilder
    # Validation utilities for options classes
    #
    # This module provides validation methods for dynamically generated
    # options classes, ensuring required arguments are present.
    module Validator
      # Define validation method on an options class
      #
      # @param klass [Class] the class to define the method on
      # @param command_def [CommandDefinition] the command definition
      def self.define_validation_method(klass, command_def)
        klass.define_method(:validate!) do
          errors = []

          # Check required arguments
          (command_def.arguments || []).each do |arg_def|
            attr_name = arg_def.name
            value = instance_variable_get("@#{attr_name}")

            # Check if required (no min specified or min > 0)
            min = arg_def.min || (arg_def.variadic ? 1 : 1)
            errors << "Missing required argument: #{attr_name}" if min.positive? && (value.nil? || (value.is_a?(Array) && value.empty?))
          end

          raise Ukiryu::Errors::ValidationError, errors.join(', ') if errors.any?
        end
      end

      # Validation error for options
      #
      class ValidationError < Ukiryu::Errors::Error
        def initialize(messages)
          super("Validation failed: #{messages.join(', ')}")
        end
      end
    end
  end
end
