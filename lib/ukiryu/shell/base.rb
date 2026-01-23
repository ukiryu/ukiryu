# frozen_string_literal: true

module Ukiryu
  module Shell
    # Base class for shell implementations
    #
    # Each shell implementation must provide:
    # - name: Symbol identifying the shell
    # - escape(string): Escape a string for this shell
    # - quote(string): Quote an argument for this shell
    # - format_path(path): Format a file path for this shell
    # - env_var(name): Format an environment variable reference
    # - join(executable, *args): Join executable and arguments into a command line
    class Base
      # Identify the shell
      #
      # @return [Symbol] the shell name
      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      # Escape a string for this shell
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        raise NotImplementedError, "#{self.class} must implement #escape"
      end

      # Quote an argument for this shell
      #
      # @param string [String] the string to quote
      # @return [String] the quoted string
      def quote(string)
        raise NotImplementedError, "#{self.class} must implement #quote"
      end

      # Format a file path for this shell
      #
      # @param path [String] the file path
      # @return [String] the formatted path
      def format_path(path)
        path
      end

      # Format an environment variable reference
      #
      # @param name [String] the variable name
      # @return [String] the formatted reference
      def env_var(name)
        raise NotImplementedError, "#{self.class} must implement #env_var"
      end

      # Join executable and arguments into a command line
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @return [String] the complete command line
      def join(executable, *args)
        raise NotImplementedError, "#{self.class} must implement #join"
      end

      # Format environment variables for command execution
      #
      # @param env_vars [Hash] environment variables to set
      # @return [Hash] formatted environment variables
      def format_environment(env_vars)
        env_vars
      end

      # Get headless environment variables (e.g., DISPLAY="" for Unix)
      #
      # @return [Hash] environment variables for headless operation
      def headless_environment
        {}
      end
    end
  end
end
