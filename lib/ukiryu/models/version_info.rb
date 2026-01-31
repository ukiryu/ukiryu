# frozen_string_literal: true

module Ukiryu
  module Models
    # Version information with detection method tracking
    #
    # Represents a version value with metadata about how it was detected.
    # Supports multiple detection methods (command, man_page, etc.) as a
    # fallback hierarchy, NOT mutually exclusive types.
    #
    # @example Command-based version
    #   VersionInfo.new(
    #     value: '3.11',
    #     method_used: :command,
    #     available_methods: [:command]
    #   )
    #
    # @example Man page fallback version
    #   VersionInfo.new(
    #     value: '2020-09-21',
    #     method_used: :man_page,
    #     available_methods: [:command, :man_page]
    #   )
    class VersionInfo
      attr_reader :value, :method_used, :available_methods

      # Initialize version info
      #
      # @param value [String] the version value (e.g., "3.11" or "2020-09-21")
      # @param method_used [Symbol] the method that succeeded (:command, :man_page, etc.)
      # @param available_methods [Array<Symbol>] all methods that were available
      def initialize(value:, method_used:, available_methods: [])
        @value = value
        @method_used = method_used
        @available_methods = available_methods
      end

      # Check if version was detected via command
      #
      # @return [Boolean] true if from command execution
      def from_command?
        method_used == :command
      end

      # Check if version was detected via man page
      #
      # @return [Boolean] true if from man page date
      def from_man_page?
        method_used == :man_page
      end

      # Check if version is from profile (hardcoded)
      #
      # @return [Boolean] true if from profile
      def from_profile?
        method_used == :profile
      end

      # Display format with context
      # Adds "(man page)" or "(profile)" suffix only for display, not stored in data
      #
      # @return [String] formatted version string
      def to_s
        case method_used
        when :command
          value
        when :man_page
          "#{value} (man page)"
        when :profile
          value
        else
          value
        end
      end

      # Hash representation
      #
      # @return [Hash] hash with value, method, and available_methods
      def to_h
        {
          value: value,
          method: method_used,
          available_methods: available_methods
        }
      end

      # Equality comparison
      #
      # @param other [Object] the object to compare
      # @return [Boolean] true if equal
      def ==(other)
        return false unless other.is_a?(VersionInfo)

        value == other.value &&
          method_used == other.method_used &&
          available_methods == other.available_methods
      end

      # Inspect representation
      #
      # @return [String] inspect string
      def inspect
        "#<VersionInfo value=\"#{value}\" method=#{method_used}>"
      end
    end
  end
end
