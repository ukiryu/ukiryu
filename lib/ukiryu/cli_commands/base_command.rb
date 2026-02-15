# frozen_string_literal: true

module Ukiryu
  module CliCommands
    # Base class for CLI commands
    #
    # Provides shared functionality for all CLI commands including
    # register setup, output formatting, and error handling.
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

      # Setup the register path
      #
      # @param custom_path [String, nil] custom register path
      def setup_register(custom_path = nil)
        register_path = custom_path || config.register || default_register_path
        return unless register_path && Dir.exist?(register_path)

        # Set UKIRYU_REGISTER env and reset the default register
        ENV['UKIRYU_REGISTER'] = register_path
        Ukiryu::Register.reset_default
      end

      # Apply CLI options to the Config instance
      # CLI options have the highest priority in the configuration chain
      def apply_cli_options_to_config
        # Thor option defaults that should not override ENV or programmatic config
        # Only apply CLI option if it's not the default value
        cli_mappings = {
          format: 'yaml', # default format in Thor
          output: nil,
          register: nil,
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

      # Get the default register path
      #
      # @return [String, nil] the default register path
      def default_register_path
        Ukiryu::Register.default.path
      rescue Ukiryu::Register::Error
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
