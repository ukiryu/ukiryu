# frozen_string_literal: true

module Ukiryu
  module Extractors
    # Native flag extraction strategy
    #
    # Attempts to extract definition using the tool's native
    # `--ukiryu-definition` flag if supported.
    class NativeExtractor < BaseExtractor
      # Native flag to try
      NATIVE_FLAG = '--ukiryu-definition'

      # Extract definition using native flag
      #
      # @return [String, nil] the YAML definition or nil if extraction failed
      def extract
        return nil unless available?

        result = execute_command([@tool_name.to_s, NATIVE_FLAG])

        return nil unless result[:exit_status].zero?
        return nil if result[:stdout].strip.empty?

        result[:stdout]
      end

      # Check if the tool supports native definition extraction
      #
      # @return [Boolean] true if the tool exists and the flag is supported
      def available?
        # First check if tool exists
        which_result = execute_command(['which', @tool_name.to_s])
        return false unless which_result[:exit_status].zero?

        # Then check if it supports the flag
        help_result = execute_command([@tool_name.to_s, '--help'])
        return false unless help_result[:exit_status].zero?

        # Check if help mentions ukiryu
        help_output = help_result[:stdout] + help_result[:stderr]
        help_output.downcase.include?('ukiryu') || help_output.include?(NATIVE_FLAG)
      end
    end
  end
end
