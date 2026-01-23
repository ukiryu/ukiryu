# frozen_string_literal: true

require_relative 'config/env_provider'
require_relative 'config/override_resolver'

module Ukiryu
  # Global configuration for Ukiryu
  # Provides unified configuration across CLI, Ruby API, and programmatic interfaces
  #
  # Configuration priority (highest to lowest):
  # 1. CLI options (passed at runtime)
  # 2. Environment variables (UKIRYU_*)
  # 3. Programmatic configuration (Config.configure)
  # 4. Default values
  #
  # @example Configure programmatically
  #   Ukiryu::Config.configure do |config|
  #     config.timeout = 30
  #     config.debug = true
  #     config.format = :json
  #   end
  #
  # @example Configure via environment variables
  #   export UKIRYU_TIMEOUT=60
  #   export UKIRYU_DEBUG=true
  #   export UKIRYU_FORMAT=json
  #
  # @example Configure via CLI options
  #   ukiryu exec ping host=example.com --format json --timeout 30
  class Config
    class << self
      def instance
        @instance ||= new
      end

      # Configure Ukiryu with a block
      # @yield [config] The configuration instance
      # @return [Config] The configuration instance
      def configure
        yield instance if block_given?
        instance
      end

      # Reset configuration to defaults
      def reset!
        @instance = new
      end

      # Delegate to instance
      def method_missing(method, ...)
        instance.send(method, ...)
      end

      def respond_to_missing?(method, include_private = false)
        instance.respond_to?(method) || super
      end
    end

    # @!attribute [r] resolver
    #   @return [OverrideResolver] The resolver for configuration values
    attr_reader :resolver

    def initialize
      @resolver = build_resolver
    end

    # Reset configuration to defaults
    def reset!
      @resolver = build_resolver
    end

    # Execution timeout in seconds
    # @return [Integer, nil] timeout in seconds, or nil for no timeout
    def timeout
      @resolver.resolve(:timeout)
    end

    # Set execution timeout
    # @param value [Integer] timeout in seconds
    def timeout=(value)
      @resolver.set_programmatic(:timeout, value)
    end

    # Debug mode flag
    # @return [Boolean] true if debug mode is enabled
    def debug
      @resolver.resolve(:debug)
    end

    # Set debug mode
    # @param value [Boolean] debug mode flag
    def debug=(value)
      @resolver.set_programmatic(:debug, value)
    end

    # Dry run flag
    # @return [Boolean] true if dry run is enabled
    def dry_run
      @resolver.resolve(:dry_run)
    end

    # Set dry run mode
    # @param value [Boolean] dry run flag
    def dry_run=(value)
      @resolver.set_programmatic(:dry_run, value)
    end

    # Output format
    # @return [Symbol] output format (:yaml, :json, :table)
    def format
      @resolver.resolve(:format)
    end

    # Set output format
    # @param value [Symbol] output format
    def format=(value)
      @resolver.set_programmatic(:format, value)
    end

    # Output file path
    # @return [String, nil] output file path, or nil for stdout
    def output
      @resolver.resolve(:output)
    end

    # Set output file path
    # @param value [String] output file path
    def output=(value)
      @resolver.set_programmatic(:output, value)
    end

    # Registry path
    # @return [String, nil] path to tool registry
    def registry
      @resolver.resolve(:registry)
    end

    # Set registry path
    # @param value [String] path to tool registry
    def registry=(value)
      @resolver.set_programmatic(:registry, value)
    end

    # Tool search paths (comma-separated)
    # @return [String, nil] comma-separated search paths
    def search_paths
      @resolver.resolve(:search_paths)
    end

    # Set search paths
    # @param value [String] comma-separated search paths
    def search_paths=(value)
      @resolver.set_programmatic(:search_paths, value)
    end

    # Use color in output
    # @return [Boolean] true if colors should be used
    def use_color
      @resolver.resolve(:use_color)
    end

    # Set color usage
    # @param value [Boolean] color usage flag
    def use_color=(value)
      @resolver.set_programmatic(:use_color, value)
    end

    # Check if colors are disabled
    # Returns true if use_color is explicitly false or if NO_COLOR is set
    # @return [Boolean] true if colors should be disabled
    def colors_disabled?
      use_color == false
    end

    # Metrics collection flag
    # @return [Boolean] true if metrics should be collected
    def metrics
      @resolver.resolve(:metrics)
    end

    # Set metrics collection
    # @param value [Boolean] metrics flag
    def metrics=(value)
      @resolver.set_programmatic(:metrics, value)
    end

    # Shell to use for command execution
    # @return [Symbol, nil] shell symbol (:bash, :zsh, :fish, :powershell, :cmd) or nil for auto-detect
    def shell
      @resolver.resolve(:shell)
    end

    # Set shell
    # @param value [Symbol, String] shell symbol or string
    def shell=(value)
      @resolver.set_programmatic(:shell, value&.to_sym)
    end

    # Set CLI option (highest priority)
    # @param key [Symbol] option key
    # @param value [Object] option value
    def set_cli_option(key, value)
      @resolver.set_cli(key, value)
    end

    # Get configuration as hash
    # @return [Hash] configuration values
    def to_h
      {
        timeout: timeout,
        debug: debug,
        dry_run: dry_run,
        metrics: metrics,
        shell: shell,
        format: format,
        output: output,
        registry: registry,
        search_paths: search_paths,
        use_color: use_color
      }
    end

    private

    def build_resolver
      defaults = {
        timeout: nil,
        debug: false,
        dry_run: false,
        metrics: false,
        shell: nil,
        format: :yaml,
        output: nil,
        registry: nil,
        search_paths: nil,
        use_color: nil # nil means auto-detect
      }

      env = EnvProvider.load_all

      OverrideResolver.new(
        defaults: defaults,
        programmatic: {},
        env: env,
        cli: {}
      )
    end
  end
end
