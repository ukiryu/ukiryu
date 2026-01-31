# frozen_string_literal: true

module Ukiryu
  # Simple thread-local storage for contexts
  #
  # @api private
  class ExecutionContext
    class ThreadLocal
      def initialize
        @key = "__ukiryu_execution_context_#{object_id}__"
      end

      def value
        Thread.current[@key]
      end

      def value=(val)
        Thread.current[@key] = val
      end
    end
  end

  # Execution context for dependency injection and execution-scoped configuration
  #
  # Provides a non-singleton alternative to Runtime.instance for better testability.
  # Wraps runtime configuration and execution-specific options in a single object.
  #
  # @example Using ExecutionContext in production
  #   context = Ukiryu::ExecutionContext.current
  #   context.platform  # => :macos
  #   context.shell     # => :bash
  #   context.register  # => '/path/to/register'
  #
  # @example Using ExecutionContext in tests
  #   context = Ukiryu::ExecutionContext.new(
  #     platform: :linux,
  #     shell: :zsh,
  #     register_path: '/test/register'
  #   )
  #   context.platform  # => :linux
  #   context.shell     # => :zsh
  class ExecutionContext
    # Thread-local storage for current context
    @current_context = ThreadLocal.new

    class << self
      # Get the current execution context
      #
      # Creates a new context from the global Runtime if none is set.
      #
      # @return [ExecutionContext] the current context
      def current
        @current_context.value ||= from_runtime
      end

      # Set the current execution context
      #
      # @param context [ExecutionContext] the context to set
      # @return [void]
      def current=(context)
        @current_context.value = context
      end

      # Execute a block with a temporary context
      #
      # @param context [ExecutionContext] the context to use
      # @yield the block to execute
      # @return [Object] the block's return value
      def with_context(context)
        old_context = @current_context.value
        @current_context.value = context
        yield
      ensure
        @current_context.value = old_context
      end

      # Create a context from the global Runtime
      #
      # @return [ExecutionContext] a new context with runtime values
      def from_runtime
        runtime = Ukiryu::Runtime.instance
        new(
          platform: runtime.platform,
          shell: runtime.shell,
          register_path: Ukiryu::Register.default_register_path,
          timeout: Ukiryu::Config.timeout,
          debug: Ukiryu::Config.debug,
          metrics: Ukiryu::Config.metrics
        )
      end

      # Reset the current context (mainly for testing)
      #
      # @api private
      def reset_current!
        @current_context.value = nil
      end
    end

    # Platform (:macos, :linux, :windows)
    #
    # @return [Symbol] the platform
    attr_reader :platform

    # Shell (:bash, :zsh, :fish, :powershell, :cmd)
    #
    # @return [Symbol] the shell
    attr_reader :shell

    # Register path for tool profiles
    #
    # @return [String, nil] the register path
    attr_reader :register_path

    # Execution timeout in seconds
    #
    # @return [Integer, nil] the timeout
    attr_reader :timeout

    # Debug mode enabled
    #
    # @return [Boolean] true if debug mode is enabled
    attr_reader :debug

    # Metrics collection enabled
    #
    # @return [Boolean] true if metrics are enabled
    attr_reader :metrics

    # User-defined options hash
    #
    # @return [Hash] additional options
    attr_reader :options

    # Create a new execution context
    #
    # @param platform [Symbol] the platform (:macos, :linux, :windows)
    # @param shell [Symbol] the shell (:bash, :zsh, :fish, :powershell, :cmd)
    # @param register_path [String, nil] the register path
    # @param timeout [Integer, nil] execution timeout in seconds
    # @param debug [Boolean] debug mode flag
    # @param metrics [Boolean] metrics collection flag
    # @param options [Hash] additional options
    def initialize(platform: nil,
                   shell: nil,
                   register_path: nil,
                   timeout: nil,
                   debug: false,
                   metrics: false,
                   options: {})
      @platform = platform
      @shell = shell
      @register_path = register_path
      @timeout = timeout
      @debug = debug
      @metrics = metrics
      @options = options
    end

    # Get the shell class for this context
    #
    # @return [Class] the shell class
    def shell_class
      Ukiryu::Shell.class_for(@shell)
    end

    # Check if running on a specific platform
    #
    # @param plat [Symbol] the platform to check
    # @return [Boolean] true if running on the specified platform
    def on_platform?(plat)
      @platform == plat.to_sym
    end

    # Check if using a specific shell
    #
    # @param sh [Symbol] the shell to check
    # @return [Boolean] true if using the specified shell
    def using_shell?(sh)
      @shell == sh.to_sym
    end

    # Check if running on Windows
    #
    # @return [Boolean] true if on Windows
    def windows?
      on_platform?(:windows)
    end

    # Check if running on macOS
    #
    # @return [Boolean] true if on macOS
    def macos?
      on_platform?(:macos)
    end

    # Check if running on Linux
    #
    # @return [Boolean] true if on Linux
    def linux?
      on_platform?(:linux)
    end

    # Check if using a Unix-like shell
    #
    # @return [Boolean] true if using bash, zsh, fish, or sh
    def unix_shell?
      %i[bash zsh fish sh].include?(@shell)
    end

    # Check if using a Windows shell
    #
    # @return [Boolean] true if using powershell or cmd
    def windows_shell?
      %i[powershell cmd].include?(@shell)
    end

    # Create a new context with merged options
    #
    # @param changes [Hash] the changes to merge
    # @return [ExecutionContext] a new context with merged values
    def merge(changes)
      self.class.new(
        platform: changes.fetch(:platform, @platform),
        shell: changes.fetch(:shell, @shell),
        register_path: changes.fetch(:register_path, @register_path),
        timeout: changes.fetch(:timeout, @timeout),
        debug: changes.fetch(:debug, @debug),
        metrics: changes.fetch(:metrics, @metrics),
        options: @options.merge(changes.fetch(:options, {}))
      )
    end

    # String representation
    #
    # @return [String] the context as a string
    def to_s
      "ExecutionContext(platform=#{@platform}, shell=#{@shell}, register=#{@register_path})"
    end

    # Inspect
    #
    # @return [String] the inspection string
    def inspect
      "#<#{self.class} #{self}>"
    end
  end
end
