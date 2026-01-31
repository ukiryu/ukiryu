# frozen_string_literal: true

module Ukiryu
  # Debug utility for conditional debug logging
  #
  # Provides a single point of control for debug logging across the codebase.
  # Debug logging is only enabled when UKIRYU_DEBUG environment variable is set.
  #
  # @example Enable debug logging
  #   ENV['UKIRYU_DEBUG'] = '1'
  #   Ukiryu.debug_enabled? # => true
  #
  # @example Disable debug logging (default)
  #   Ukiryu.debug_enabled? # => false
  module Debug
    class << self
      # Check if debug logging is enabled
      #
      # Debug is enabled ONLY when UKIRYU_DEBUG environment variable is set.
      # The ENV['CI'] check was removed to prevent debug output from polluting
      # JSON/YAML output in automated tests.
      #
      # @return [Boolean] true if debug mode is enabled
      def enabled?
        ENV['UKIRYU_DEBUG'] || ENV['UKIRYU_DEBUG_EXECUTABLE']
      end

      # Log a debug message to stderr
      #
      # @param message [String] the debug message
      def log(message)
        warn "[UKIRYU DEBUG] #{message}" if enabled?
      end
    end
  end

  # Convenience method for checking if debug is enabled
  #
  # @return [Boolean] true if debug mode is enabled
  def self.debug_enabled?
    Debug.enabled?
  end
end
