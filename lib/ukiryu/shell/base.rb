# frozen_string_literal: true

module Ukiryu
  module Shell
    # Base class for shell implementations
    #
    # Each shell implementation must provide:
    # - SHELL_NAME: Symbol identifying the shell
    # - PLATFORM: Symbol for platform grouping (:unix, :windows, :powershell)
    # - EXECUTABLE: Default executable path/name
    # - name: Instance method returning the shell name (for compatibility)
    #
    # Each shell implementation must provide:
    # - escape(string): Escape a string for this shell
    # - quote(string): Quote an argument for this shell
    # - format_path(path): Format a file path for this shell
    # - env_var(name): Format an environment variable reference
    # - join(executable, *args): Join executable and arguments into a command line
    #
    # Each shell class also provides:
    # - detect_alias(command_name): Detect if a command is a shell alias
    class Base
      # Symbol identifying the shell (override in subclass)
      SHELL_NAME = nil

      # Platform grouping (override in subclass)
      PLATFORM = nil

      # Default executable path (override in subclass)
      EXECUTABLE = nil

      # Pre-compiled regex patterns for performance
      WHITESPACE_PATTERN = /\s/.freeze
      SPECIAL_CHARS_PATTERN = /[\s&*()\[\]{}|;<>?`~!@%"]/.freeze

      # Detect if a command is a shell alias
      #
      # Returns alias information if the command is an alias, nil otherwise.
      # Subclasses should override to provide shell-specific alias detection.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] {definition: "...", target: "..."} or nil if not an alias
      def self.detect_alias(_command_name)
        # Default implementation - no alias detection
        nil
      end

      # Get shell capabilities
      #
      # Defines what features and environment behaviors this shell supports.
      # Subclasses should override to customize capabilities.
      #
      # @return [Hash{Symbol => Object}] capability flags and values
      # @option capabilities [Boolean] :supports_display - Shell supports DISPLAY for GUI apps
      # @option capabilities [Boolean] :supports_ansi_colors - Shell supports ANSI color codes
      # @option capabilities [Encoding] :encoding - Ruby's Encoding for output
      def capabilities
        {
          supports_display: true,
          supports_ansi_colors: true,
          encoding: Encoding::UTF_8
        }
      end

      # Check if shell supports a specific capability
      #
      # @param capability [Symbol] the capability to check
      # @return [Boolean] true if the capability is supported
      def supports?(capability)
        capabilities.key?(capability) && capabilities[capability]
      end

      # Get the shell's output encoding
      #
      # @return [Encoding] the encoding for shell output
      def encoding
        capabilities[:encoding]
      end

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

      # Check if a string needs quoting
      # Strings with spaces, special chars, or empty strings need quoting
      #
      # @param string [String] the string to check
      # @return [Boolean] true if quoting is needed
      def needs_quoting?(string)
        str = string.to_s
        # Empty strings need quoting
        return true if str.empty?
        # Strings with whitespace need quoting (use pre-compiled pattern)
        return true if str =~ WHITESPACE_PATTERN
        # Strings with shell special characters need quoting (use pre-compiled pattern)
        return true if str =~ SPECIAL_CHARS_PATTERN

        false
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

      # Execute a command using this shell
      #
      # This method provides OOP encapsulation of shell-specific command execution.
      # Each shell subclass implements its own execution strategy.
      # The Environment object is stored and converted to Hash only at Open3 call site.
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables (converted to Hash at Open3 site)
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command(executable, args, env, timeout, cwd = nil)
        raise NotImplementedError, "#{self.class} must implement #execute_command"
      end

      # Execute a command with stdin input using this shell
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables (converted to Hash at Open3 site)
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @param stdin_data [String, IO] stdin input data
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command_with_stdin(executable, args, env, timeout, cwd, stdin_data)
        raise NotImplementedError, "#{self.class} must implement #execute_command_with_stdin"
      end

      # Convert Environment to Hash for Open3
      #
      # This is the ONLY place where Environment should be converted to Hash.
      # All Shell subclasses must use this method before calling Open3.
      #
      # @param env [Environment, Hash] the environment (Environment or legacy Hash)
      # @return [Hash] environment variables for Open3
      def environment_to_h(env)
        env.is_a?(Environment) ? env.to_h : env
      end
    end
  end
end
