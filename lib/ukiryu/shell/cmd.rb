# frozen_string_literal: true

require_relative 'base'

module Ukiryu
  module Shell
    # Windows cmd.exe shell implementation
    #
    # cmd.exe uses caret (^) as the escape character and double quotes
    # for strings containing spaces. Environment variables use %VAR% syntax.
    class Cmd < Base
      def name
        :cmd
      end

      # Escape a string for cmd.exe
      # Caret is the escape character for special characters: % ^ < > & |
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        string.to_s.gsub(/[%^<>&|]/) { '^$&' }
      end

      # Quote an argument for cmd.exe
      # Uses double quotes for strings with spaces
      #
      # @param string [String] the string to quote
      # @return [String] the quoted string
      def quote(string)
        if string.to_s =~ /[ \t]/
          # Contains whitespace, use double quotes
          # Note: cmd.exe doesn't escape quotes inside double quotes the same way
          "\"#{string}\""
        else
          # No whitespace, escape special characters
          escape(string)
        end
      end

      # Format a file path for cmd.exe
      # Convert forward slashes to backslashes
      #
      # @param path [String] the file path
      # @return [String] the formatted path
      def format_path(path)
        path.to_s.gsub('/', '\\')
      end

      # Format an environment variable reference
      #
      # @param name [String] the variable name
      # @return [String] the formatted reference (%VAR%)
      def env_var(name)
        "%#{name}%"
      end

      # Join executable and arguments into a command line
      # Uses smart quoting: only quote arguments that need it
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @return [String] the complete command line
      def join(executable, *args)
        args_formatted = args.map do |a|
          if needs_quoting?(a)
            quote(a)
          else
            # For simple strings, pass without quotes
            # cmd.exe treats them as literal strings
            escape(a)
          end
        end
        [executable, *args_formatted].join(' ')
      end

      # cmd.exe doesn't need DISPLAY variable
      #
      # @return [Hash] empty hash (no headless environment needed)
      def headless_environment
        {}
      end
    end
  end
end
