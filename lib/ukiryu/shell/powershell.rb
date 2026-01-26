# frozen_string_literal: true

require_relative 'base'

module Ukiryu
  module Shell
    # PowerShell shell implementation
    #
    # PowerShell uses single quotes for literal strings and backtick
    # for escaping special characters inside double quotes.
    # Environment variables are referenced with $ENV:NAME syntax.
    class PowerShell < Base
      def name
        :powershell
      end

      # Escape a string for PowerShell
      # Backtick is the escape character for: ` $ "
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        string.to_s.gsub(/[`"$]/) { '`$&' }
      end

      # Quote an argument for PowerShell
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
      # @return [String] the formatted reference ($ENV:NAME)
      def env_var(name)
        "$ENV:#{name}"
      end

      # Join executable and arguments into a command line
      # Uses smart quoting: only quote arguments that need it
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @return [String] the complete command line
      def join(executable, *args)
        # Quote executable if it needs quoting (e.g., contains spaces)
        exe_formatted = needs_quoting?(executable) ? quote(executable) : executable

        args_formatted = args.map do |a|
          if needs_quoting?(a)
            quote(a)
          else
            # For simple strings, pass without quotes
            # PowerShell treats them as literal strings
            a
          end
        end
        [exe_formatted, *args_formatted].join(' ')
      end

      # PowerShell doesn't need DISPLAY variable
      #
      # @return [Hash] empty hash (no headless environment needed)
      def headless_environment
        {}
      end
    end
  end
end
