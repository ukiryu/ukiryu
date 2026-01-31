# frozen_string_literal: true

module Ukiryu
  module Shell
    # POSIX sh shell implementation
    #
    # sh uses the same quoting and escaping rules as Bash.
    class Sh < UnixBase
      SHELL_NAME = :sh
      EXECUTABLE = 'sh'

      # Detect if a command is a POSIX sh alias
      #
      # POSIX sh has 'type' but may not have alias detection in all implementations.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] {definition: "...", target: "..."} or nil if not an alias
      def self.detect_alias(command_name)
        # POSIX sh has 'type' but may not have alias detection
        result = `type #{command_name} 2>/dev/null`
        return nil unless result

        { definition: result.strip, target: ::Regexp.last_match(1) } if result =~ /^#{command_name} is aliased to `(.*)'`$/
        nil
      end

      def name
        :sh
      end

      # Get the sh command name to search for
      #
      # @return [String] the sh command name
      def shell_command
        'sh'
      end

      # sh uses the same escaping as Bash
      def escape(string)
        string.to_s.gsub("'") { "'\\''" }
      end

      # sh uses the same quoting as Bash
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
