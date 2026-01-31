# frozen_string_literal: true

module Ukiryu
  module Shell
    # Fish shell implementation
    #
    # Fish uses similar quoting to Bash for most cases.
    class Fish < UnixBase
      SHELL_NAME = :fish
      EXECUTABLE = 'fish'

      # Detect if a command is a Fish alias
      #
      # Fish uses 'type' command with different output format than Bash.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] {definition: "...", target: "..."} or nil if not an alias
      def self.detect_alias(command_name)
        # Fish uses 'type' command with different output
        result = `type #{command_name} 2>/dev/null`
        return nil unless result

        if result.include?("#{command_name} is an alias") && (result =~ /alias #{command_name} ['"](.*)['"]/)
          # Parse fish alias format
          # Format: "alias ll 'ls -l --color=auto'"
          { definition: result.strip, target: ::Regexp.last_match(1) }
        end
        nil
      end

      def name
        :fish
      end

      # Get the fish command name to search for
      #
      # @return [String] the fish command name
      def shell_command
        'fish'
      end

      # Fish uses the same escaping as Bash
      def escape(string)
        string.to_s.gsub("'") { "'\\''" }
      end

      # Fish uses the same quoting as Bash
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
