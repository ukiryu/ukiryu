# frozen_string_literal: true

module Ukiryu
  module Definition
    # Result of a definition validation
    #
    # This class represents the result of validating a tool definition
    # against a JSON Schema or other validation rules.
    class ValidationResult
      attr_reader :errors, :warnings, :schema_path

      def initialize(valid:, errors: [], warnings: [], schema_path: nil)
        @valid = valid
        @errors = errors
        @warnings = warnings
        @schema_path = schema_path
      end

      # Check if validation passed
      #
      # @return [Boolean] true if validation passed
      def valid?
        @valid
      end

      # Check if validation failed
      #
      # @return [Boolean] true if validation failed
      def invalid?
        !@valid
      end

      # Check if there are any errors
      #
      # @return [Boolean] true if there are errors
      def has_errors?
        !@errors.empty?
      end

      # Check if there are any warnings
      #
      # @return [Boolean] true if there are warnings
      def has_warnings?
        !@warnings.empty?
      end

      # Get total issue count
      #
      # @return [Integer] total number of issues (errors + warnings)
      def issue_count
        @errors.length + @warnings.length
      end

      # Get error count
      #
      # @return [Integer] number of errors
      def error_count
        @errors.length
      end

      # Get warning count
      #
      # @return [Integer] number of warnings
      def warning_count
        @warnings.length
      end

      # Create a successful validation result
      #
      # @return [ValidationResult] a successful result
      def self.success
        new(valid: true)
      end

      # Create a failed validation result
      #
      # @param errors [Array<String>] validation errors
      # @param warnings [Array<String>] validation warnings
      # @return [ValidationResult] a failed result
      def self.failure(errors, warnings = [])
        new(valid: false, errors: errors, warnings: warnings)
      end

      # Create a result with warnings
      #
      # @param warnings [Array<String>] validation warnings
      # @return [ValidationResult] a result with warnings
      def self.with_warnings(warnings)
        new(valid: true, warnings: warnings)
      end

      # Convert to hash
      #
      # @return [Hash] hash representation
      def to_h
        {
          valid: @valid,
          errors: @errors,
          warnings: @warnings,
          schema_path: @schema_path,
          error_count: error_count,
          warning_count: warning_count
        }
      end

      # Convert to JSON
      #
      # @return [String] JSON representation
      def to_json(*args)
        require 'json'
        to_h.to_json(*args)
      end

      # Human-readable summary
      #
      # @return [String] summary text
      def summary
        if valid?
          if has_warnings?
            "Valid with #{warning_count} warning(s)"
          else
            'Valid'
          end
        else
          msg = "Invalid (#{error_count} error(s)"
          msg += ", #{warning_count} warning(s)" if has_warnings?
          "#{msg})"
        end
      end

      # Detailed message string
      #
      # @return [String] detailed message
      def to_s
        output = []
        output << "Validation: #{summary}"

        if has_errors?
          output << ''
          output << 'Errors:'
          @errors.each_with_index do |error, i|
            output << "  #{i + 1}. #{error}"
          end
        end

        if has_warnings?
          output << ''
          output << 'Warnings:'
          @warnings.each_with_index do |warning, i|
            output << "  #{i + 1}. #{warning}"
          end
        end

        output.join("\n")
      end
    end
  end
end
