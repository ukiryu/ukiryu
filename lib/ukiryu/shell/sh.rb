# frozen_string_literal: true

require_relative 'unix_base'

module Ukiryu
  module Shell
    # POSIX sh shell implementation
    #
    # sh uses the same quoting and escaping rules as Bash.
    class Sh < UnixBase
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
