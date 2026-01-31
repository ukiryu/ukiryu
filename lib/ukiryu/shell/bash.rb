# frozen_string_literal: true

module Ukiryu
  module Shell
    # Bash shell implementation
    #
    # Bash uses single quotes for literal strings and backslash for escaping.
    # Environment variables are referenced with $VAR syntax.
    class Bash < UnixBase
      SHELL_NAME = :bash
      EXECUTABLE = 'bash'

      # Detect if a command is a Bash alias
      #
      # Uses the 'type' builtin which returns "X is alias Y" for aliases.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] {definition: "...", target: "..."} or nil if not an alias
      def self.detect_alias(command_name)
        # Use 'type' builtin which returns "alias is alias" for aliases
        result = `type #{command_name} 2>/dev/null`
        return nil unless result

        if result =~ /^#{command_name} is alias (.*)$/
          alias_definition = ::Regexp.last_match(1)
          # Extract target from alias definition
          # Format: alias ll='ls -l'
          if alias_definition =~ /^'(.*)'$/
            target = ::Regexp.last_match(1)
            target = extract_command_from_alias(target)
            { definition: result.strip, target: target }
          end
        end
        nil
      end

      # Extract the first word from an alias definition
      #
      # @param alias_def [String] the alias definition
      # @return [String] the first word (command)
      def self.extract_command_from_alias(alias_def)
        # Extract the first word from the alias definition
        # e.g., "ls -l --color=auto" -> "ls"
        alias_def.split(/\s+/).first
      end

      def name
        :bash
      end

      # Get the bash command name to search for
      #
      # @return [String] the bash command name
      def shell_command
        'bash'
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
        [quote(executable), *args.map { |a| quote(a) }].join(' ')
      end

      # Get headless environment (disable DISPLAY on Unix)
      #
      # For macOS, adds additional variables to prevent GUI initialization
      # that can cause crashes in GUI applications like Inkscape.
      #
      # @return [Hash] environment variables for headless operation
      def headless_environment
        env = {}

        # Completely remove DISPLAY instead of setting to empty string
        # This ensures full headless mode with no display connection
        # The executor will exclude this key from the environment entirely

        # Add macOS-specific environment variables to prevent GUI initialization
        if Ukiryu::Platform.detect == :macos
          env['NSAppleEventsSuppressStartupAlert'] = 'true' # Suppress Apple Events
          env['NSUIElement'] = '1' # Run as background agent
          env['GDK_BACKEND'] = 'x11' # Force X11 backend (respects missing DISPLAY)
        end

        env
      end
    end
  end
end
