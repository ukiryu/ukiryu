# frozen_string_literal: true

require_relative '../config'

module Ukiryu
  module CliCommands
    # Base class for CLI commands
    #
    # Provides shared functionality for all CLI commands including
    # registry setup, output formatting, and error handling.
    #
    # @abstract Subclasses must implement the `run` method
    class BaseCommand
      attr_reader :options, :config

      # Initialize a new command
      #
      # @param options [Hash] command options from Thor
      def initialize(options = {})
        @options = options
        @config = Ukiryu::Config.instance
        apply_cli_options_to_config
      end

      # Execute the command
      #
      # Subclasses must implement this method
      #
      # @raise [NotImplementedError] if not implemented in subclass
      def run
        raise NotImplementedError, "#{self.class} must implement #run"
      end

      # Setup the registry path
      #
      # @param custom_path [String, nil] custom registry path
      def setup_registry(custom_path = nil)
        registry_path = custom_path || config.registry || default_registry_path
        return unless registry_path && Dir.exist?(registry_path)

        Registry.default_registry_path = registry_path
      end

      # Apply CLI options to the Config instance
      # CLI options have the highest priority in the configuration chain
      def apply_cli_options_to_config
        # Thor option defaults that should not override ENV or programmatic config
        # Only apply CLI option if it's not the default value
        cli_mappings = {
          format: 'yaml', # default format in Thor
          output: nil,
          registry: nil,
          timeout: nil,
          shell: nil
        }

        cli_mappings.each do |cli_key, default_value|
          next unless options.key?(cli_key)

          # Only set CLI option if it's not the default value
          # This allows ENV and programmatic config to take precedence when user doesn't specify
          option_value = options[cli_key]
          should_set = if default_value.nil?
                         # No default, always set
                         !option_value.nil? && !option_value.empty?
                       else
                         # Only set if different from default (user explicitly specified)
                         option_value != default_value
                       end

          config.set_cli_option(cli_key, option_value) if should_set
        end

        # Handle boolean options from Thor
        config.set_cli_option(:debug, options[:verbose]) if options.key?(:verbose)

        # Handle dry_run option
        return unless options.key?(:dry_run)

        config.set_cli_option(:dry_run, options[:dry_run])
      end

      # Get the default registry path
      #
      # @return [String, nil] the default registry path
      def default_registry_path
        # Try multiple approaches to find the registry
        # Note: ENV and Config.registry are already checked by setup_registry

        # 1. Try relative to gem location
        gem_root = File.dirname(File.dirname(File.dirname(__FILE__)))
        registry_path = File.join(gem_root, '..', 'register')
        return File.expand_path(registry_path) if Dir.exist?(registry_path)

        # 2. Try from current directory (development setup)
        current = File.expand_path('../register', Dir.pwd)
        return current if Dir.exist?(current)

        # 3. Try from parent directory
        parent = File.expand_path('../../register', Dir.pwd)
        return parent if Dir.exist?(parent)

        nil
      end

      # Convert string keys to symbols
      #
      # @param hash [Hash] hash with string keys
      # @return [Hash] hash with symbol keys
      def stringify_keys(hash)
        hash.transform_keys(&:to_sym)
      end

      protected

      # Say output (Thor compatibility)
      #
      # Respects the use_color configuration option and NO_COLOR environment variable.
      #
      # @param message [String] the message
      # @param color [Symbol] the color
      def say(message, color = nil)
        # Check if colors should be disabled
        # Config handles both use_color setting and NO_COLOR environment variable
        colors_disabled = config.colors_disabled?

        if color && !colors_disabled
          # Use ANSI color codes
          colors = {
            black: 30,
            red: 31,
            green: 32,
            yellow: 33,
            blue: 34,
            magenta: 35,
            cyan: 36,
            white: 37,
            dim: 2 # bright/black for dim
          }
          code = colors[color] || 37
          puts "\e[#{code}m#{message}\e[0m"
        else
          puts message
        end
      end

      # Exit with error message
      #
      # @param message [String] the error message
      def error!(message)
        raise Thor::Error, message
      end
    end
  end
end
