# frozen_string_literal: true

module Ukiryu
  module Extractors
    # Main extractor class that orchestrates extraction strategies
    #
    # Tries multiple extraction strategies in order:
    # 1. Native flag extraction (--ukiryu-definition)
    # 2. Help parsing (--help output)
    #
    # @example Extract definition from a tool
    #   result = Ukiryu::Extractor.extract(:git)
    #   if result[:success]
    #     puts result[:yaml]
    #   else
    #     puts "Failed: #{result[:error]}"
    #   end
    class Extractor
      # Extract definition from a tool
      #
      # Tries multiple extraction strategies in order until one succeeds.
      #
      # @param tool_name [String, Symbol] the tool name
      # @param options [Hash] extraction options
      # @option options [Symbol] :method specific method to use (:native, :help, :auto)
      # @option options [Boolean] :verbose enable verbose output
      # @return [Hash] result with :success, :yaml, :method, :error keys
      def self.extract(tool_name, options = {})
        new(tool_name, options).extract
      end

      # Initialize the extractor
      #
      # @param tool_name [String, Symbol] the tool name
      # @param options [Hash] extraction options
      def initialize(tool_name, options = {})
        @tool_name = tool_name
        @options = options
      end

      # Extract definition using available strategies
      #
      # @return [Hash] result with :success, :yaml, :method, :error keys
      def extract
        method = @options[:method] || :auto

        case method
        when :auto
          extract_auto
        when :native
          extract_with_native
        when :help
          extract_with_help
        else
          {
            success: false,
            error: "Unknown extraction method: #{method}",
            method: nil,
            yaml: nil
          }
        end
      end

      private

      # Try all extraction strategies in order
      #
      # @return [Hash] result hash
      def extract_auto
        # Try native flag first
        result = extract_with_native
        return result if result[:success]

        # Fall back to help parsing
        extract_with_help
      end

      # Extract using native flag
      #
      # @return [Hash] result hash
      def extract_with_native
        extractor = Ukiryu::Extractors::NativeExtractor.new(@tool_name, @options)

        unless extractor.available?
          return {
            success: false,
            error: "Tool '#{@tool_name}' does not support native definition extraction",
            method: :native,
            yaml: nil
          }
        end

        yaml = extractor.extract

        if yaml
          {
            success: true,
            yaml: yaml,
            method: :native,
            error: nil
          }
        else
          {
            success: false,
            error: 'Native extraction failed',
            method: :native,
            yaml: nil
          }
        end
      end

      # Extract using help parser
      #
      # @return [Hash] result hash
      def extract_with_help
        extractor = Ukiryu::Extractors::HelpParser.new(@tool_name, @options)

        unless extractor.available?
          return {
            success: false,
            error: "Tool '#{@tool_name}' does not have help output",
            method: :help,
            yaml: nil
          }
        end

        yaml = extractor.extract

        if yaml
          {
            success: true,
            yaml: yaml,
            method: :help,
            error: nil
          }
        else
          {
            success: false,
            error: 'Help parsing failed',
            method: :help,
            yaml: nil
          }
        end
      end
    end
  end
end
