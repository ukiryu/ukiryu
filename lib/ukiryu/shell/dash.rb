# frozen_string_literal: true

module Ukiryu
  module Shell
    # Dash (Debian Almquist Shell) implementation
    #
    # Dash is a POSIX-compliant shell that is commonly used as /bin/sh
    # on Debian, Ubuntu, and other Linux distributions.
    # It is similar to bash but more minimal and faster.
    #
    # Dash uses single quotes for literal strings and backslash for escaping,
    # just like bash. Environment variables use $VAR syntax.
    class Dash < UnixBase
      SHELL_NAME = :dash
      EXECUTABLE = 'dash'

      # Detect if a command is a Dash alias
      #
      # Dash is POSIX-compliant and uses the same 'type' builtin as sh.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] {definition: "...", target: "..."} or nil if not an alias
      def self.detect_alias(command_name)
        # Dash uses POSIX sh's 'type' builtin
        Sh.detect_alias(command_name)
      end

      def name
        :dash
      end

      # Get the dash command name to search for
      #
      # @return [String] the dash command name
      def shell_command
        'dash'
      end

      # Escape a string for Dash
      # Single quotes are literal (no escaping inside), so we end the quote,
      # add an escaped quote, and restart the quote. Same as bash.
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        string.to_s.gsub("'") { "'\\''" }
      end

      # Quote an argument for Dash
      # Uses single quotes for literal strings (same as bash)
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
        [quote(executable), *args.map { |a| quote(a) }].join(' ')
      end

      # Get headless environment (disable DISPLAY on Unix)
      #
      # Dash doesn't have platform-specific headless behavior,
      # so it returns an empty hash.
      #
      # @return [Hash] empty hash
      def headless_environment
        {}
      end
    end
  end
end
