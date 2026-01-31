# frozen_string_literal: true

module Ukiryu
  module Shell
    # Zsh shell implementation
    #
    # Zsh uses the same quoting and escaping rules as Bash.
    class Zsh < UnixBase
      SHELL_NAME = :zsh
      EXECUTABLE = 'zsh'

      # Detect if a command is a Zsh alias
      #
      # Zsh uses the same 'type' builtin as Bash.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] {definition: "...", target: "..."} or nil if not an alias
      def self.detect_alias(command_name)
        # Zsh uses the same 'type' builtin as Bash
        Bash.detect_alias(command_name)
      end

      def name
        :zsh
      end

      # Get the zsh command name to search for
      #
      # @return [String] the zsh command name
      def shell_command
        'zsh'
      end

      # Zsh uses the same escaping as Bash
      def escape(string)
        string.to_s.gsub("'") { "'\\''" }
      end

      # Zsh uses the same quoting as Bash
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
    end
  end
end
