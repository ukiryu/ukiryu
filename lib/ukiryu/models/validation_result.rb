# frozen_string_literal: true

module Ukiryu
  module Models
    # Result of validating a tool profile against the schema
    #
    # Contains validation status and any errors found during validation.
    class ValidationResult
      attr_reader :tool_name, :valid, :errors

      # Create a new validation result
      #
      # @param tool_name [String] the tool name that was validated
      # @param valid [Boolean] whether validation passed
      # @param errors [Array<String>] list of validation errors
      def initialize(tool_name:, valid:, errors: [])
        @tool_name = tool_name
        @valid = valid
        @errors = errors
      end

      # Create a valid result (no errors)
      #
      # @param tool_name [String] the tool name
      # @return [ValidationResult] a valid result
      def self.valid(tool_name)
        new(tool_name: tool_name, valid: true, errors: [])
      end

      # Create an invalid result with errors
      #
      # @param tool_name [String] the tool name
      # @param errors [Array<String>] list of validation errors
      # @return [ValidationResult] an invalid result
      def self.invalid(tool_name, errors)
        new(tool_name: tool_name, valid: false, errors: errors)
      end

      # Create a result for a tool not found
      #
      # @param tool_name [String] the tool name
      # @return [ValidationResult] a not found result
      def self.not_found(tool_name)
        new(tool_name: tool_name, valid: false, errors: ['Tool not found'])
      end

      # Get a human-readable status message
      #
      # @return [String] status message
      def status_message
        if valid?
          "✓ Valid"
        else
          "✗ Invalid (#{errors.size} error#{errors.size == 1 ? '' : 's'})"
        end
      end

      # Check if validation passed
      #
      # @return [Boolean] true if valid
      def valid?
        @valid
      end

      # Check if validation failed
      #
      # @return [Boolean] true if invalid
      def invalid?
        !@valid
      end

      # Check if tool was not found
      #
      # @return [Boolean] true if tool not found
      def not_found?
        @errors == ['Tool not found']
      end
    end
  end
end
