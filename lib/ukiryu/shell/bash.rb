# frozen_string_literal: true

require_relative 'base'

module Ukiryu
  module Shell
    # Bash shell implementation
    #
    # Bash uses single quotes for literal strings and backslash for escaping.
    # Environment variables are referenced with $VAR syntax.
    class Bash < Base
      def name
        :bash
      end

      # Escape a string for Bash
      # Single quotes are literal (no escaping inside), so we end the quote,
      # add an escaped quote, and restart the quote.
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        string.to_s.gsub("'") { "'\\''" }
      end

      # Quote an argument for Bash
      # Uses single quotes for literal strings
      #
      # @param string [String] the string to quote
      # @return [String] the quoted string
      def quote(string)
        "'#{escape(string)}'"
      end

      # Format an environment variable reference
      #
      # @param name [String] the variable name
      # @return [String] the formatted reference ($VAR)
      def env_var(name)
        "$#{name}"
      end

      # Join executable and arguments into a command line
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @return [String] the complete command line
      def join(executable, *args)
        [executable, *args.map { |a| quote(a) }].join(' ')
      end

      # Get headless environment (disable DISPLAY on Unix)
      #
      # @return [Hash] environment variables for headless operation
      def headless_environment
        { 'DISPLAY' => '' }
      end
    end
  end
end
