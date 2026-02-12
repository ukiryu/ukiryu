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
  #
  # @example Log with category
  #   Ukiryu::Debug.log("Found executable", category: :executable)
  module Debug
    class << self
      # Check if debug logging is enabled for a category
      #
      # @param category [Symbol, nil] the category (:executable for UKIRYU_DEBUG_EXECUTABLE)
      # @return [Boolean] true if debug mode is enabled
      def enabled?(category = nil)
        case category
        when :executable
          ENV['UKIRYU_DEBUG_EXECUTABLE'] || (defined?(Platform) && Platform.windows? && ENV['CI'])
        else
          ENV['UKIRYU_DEBUG'] || ENV['UKIRYU_DEBUG_EXECUTABLE']
        end
      end

      # Log a debug message to stderr
      #
      # @param message [String] the debug message
      # @param category [Symbol, nil] optional category (:executable for executable discovery)
      # @param context [Hash] optional context data
      def log(message, category: nil, context: {})
        return unless enabled?(category)

        prefix = "[UKIRYU DEBUG#{category ? " #{category.to_s.upcase}" : ''}]"
        details = context.empty? ? '' : " (#{context.map { |k, v| "#{k}=#{v.inspect}" }.join(', ')})"
        warn "#{prefix} #{message}#{details}"
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
