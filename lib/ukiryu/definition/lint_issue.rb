# frozen_string_literal: true

module Ukiryu
  module Definition
    # A linting issue found in a definition
    #
    # This class represents a single linting issue with severity,
    # message, location, and optional suggestion.
    class LintIssue
      # Severity levels
      SEVERITY_ERROR = :error
      SEVERITY_WARNING = :warning
      SEVERITY_INFO = :info
      SEVERITY_STYLE = :style

      attr_reader :severity, :message, :location, :suggestion, :rule_id

      def initialize(severity:, message:, location: nil, suggestion: nil, rule_id: nil)
        @severity = severity
        @message = message
        @location = location
        @suggestion = suggestion
        @rule_id = rule_id
      end

      # Check if this is an error
      #
      # @return [Boolean] true if severity is error
      def error?
        @severity == SEVERITY_ERROR
      end

      # Check if this is a warning
      #
      # @return [Boolean] true if severity is warning
      def warning?
        @severity == SEVERITY_WARNING
      end

      # Check if this is info
      #
      # @return [Boolean] true if severity is info
      def info?
        @severity == SEVERITY_INFO
      end

      # Check if this is style
      #
      # @return [Boolean] true if severity is style
      def style?
        @severity == SEVERITY_STYLE
      end

      # Check if this issue has a suggestion
      #
      # @return [Boolean] true if suggestion is present
      def has_suggestion?
        !@suggestion.nil? && !@suggestion.empty?
      end

      # Check if this issue has a location
      #
      # @return [Boolean] true if location is present
      def has_location?
        !@location.nil? && !@location.empty?
      end

      # Get severity as a readable string
      #
      # @return [String] severity string
      def severity_string
        @severity.to_s.upcase
      end

      # Convert to hash
      #
      # @return [Hash] hash representation
      def to_h
        {
          severity: @severity,
          severity_string: severity_string,
          message: @message,
          location: @location,
          suggestion: @suggestion,
          rule_id: @rule_id
        }
      end

      # Format as string
      #
      # @return [String] formatted issue
      def to_s
        output = "[#{severity_string}] #{@message}"
        output += " (at #{@location})" if has_location?
        output += "\n  Suggestion: #{@suggestion}" if has_suggestion?
        output
      end

      # Create an error issue
      #
      # @param message [String] error message
      # @param location [String, nil] issue location
      # @param suggestion [String, nil] fix suggestion
      # @param rule_id [String, nil] rule identifier
      # @return [LintIssue] error issue
      def self.error(message, location: nil, suggestion: nil, rule_id: nil)
        new(
          severity: SEVERITY_ERROR,
          message: message,
          location: location,
          suggestion: suggestion,
          rule_id: rule_id
        )
      end

      # Create a warning issue
      #
      # @param message [String] warning message
      # @param location [String, nil] issue location
      # @param suggestion [String, nil] fix suggestion
      # @param rule_id [String, nil] rule identifier
      # @return [LintIssue] warning issue
      def self.warning(message, location: nil, suggestion: nil, rule_id: nil)
        new(
          severity: SEVERITY_WARNING,
          message: message,
          location: location,
          suggestion: suggestion,
          rule_id: rule_id
        )
      end

      # Create an info issue
      #
      # @param message [String] info message
      # @param location [String, nil] issue location
      # @param suggestion [String, nil] fix suggestion
      # @param rule_id [String, nil] rule identifier
      # @return [LintIssue] info issue
      def self.info(message, location: nil, suggestion: nil, rule_id: nil)
        new(
          severity: SEVERITY_INFO,
          message: message,
          location: location,
          suggestion: suggestion,
          rule_id: rule_id
        )
      end

      # Create a style issue
      #
      # @param message [String] style message
      # @param location [String, nil] issue location
      # @param suggestion [String, nil] fix suggestion
      # @param rule_id [String, nil] rule identifier
      # @return [LintIssue] style issue
      def self.style(message, location: nil, suggestion: nil, rule_id: nil)
        new(
          severity: SEVERITY_STYLE,
          message: message,
          location: location,
          suggestion: suggestion,
          rule_id: rule_id
        )
      end
    end
  end
end
