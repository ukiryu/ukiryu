# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Ukiryu
  module CliCommands
    # Configuration management command
    class ConfigCommand < BaseCommand
      CONFIG_DIR = File.expand_path('~/.ukiryu')
      CONFIG_FILE = File.join(CONFIG_DIR, 'config.yml')

      # Execute the config command
      #
      # @param action [String] the action (list, get, set, unset)
      # @param key [String, nil] the config key
      # @param value [String, nil] the config value
      def run(action = 'list', key = nil, value = nil)
        setup_register

        case action
        when 'list'
          action_list
        when 'get'
          action_get(key)
        when 'set'
          action_set(key, value)
        when 'unset'
          action_unset(key)
        else
          error! "Unknown action: #{action}\nValid actions: list, get, set, unset"
        end
      end

      private

      # List all configuration
      def action_list
        say 'Current configuration:', :cyan
        say '', :clear

        # Get actual register info for better display
        register_display = format_register_display

        config_data = {
          'Register' => register_display,
          'Timeout' => format_config_value(config.timeout, '(no timeout)'),
          'Debug' => format_config_value(config.debug),
          'Dry run' => format_config_value(config.dry_run),
          'Metrics' => format_config_value(config.metrics),
          'Shell' => format_config_value(config.shell, '(auto-detect)'),
          'Format' => format_config_value(config.format),
          'Output' => format_config_value(config.output, '(stdout)'),
          'Use color' => format_config_value(config.use_color)
        }

        config_data.each do |k, v|
          value_str = v.is_a?(String) ? "'#{v}'" : v.to_s
          say "  #{k.ljust(20)}: #{value_str}", :white
        end

        # Show persistent config if exists
        say '', :clear
        if File.exist?(CONFIG_FILE)
          say 'Persistent configuration:', :cyan
          say "  File: #{CONFIG_FILE}", :dim

          persistent = load_persistent_config
          if persistent && !persistent.empty?
            persistent.each do |k, v|
              say "  #{k}: #{v}", :dim
            end
          else
            say '  (empty)', :dim
          end
        else
          say 'No persistent configuration file found.', :dim
          say "  Config would be saved to: #{CONFIG_FILE}", :dim
        end

        # Show environment variables
        say '', :clear
        say 'Environment variables:', :cyan
        env_vars = {
          'UKIRYU_REGISTER' => ENV['UKIRYU_REGISTER'],
          'UKIRYU_TIMEOUT' => ENV['UKIRYU_TIMEOUT'],
          'UKIRYU_DEBUG' => ENV['UKIRYU_DEBUG'],
          'UKIRYU_DRY_RUN' => ENV['UKIRYU_DRY_RUN'],
          'UKIRYU_METRICS' => ENV['UKIRYU_METRICS'],
          'UKIRYU_SHELL' => ENV['UKIRYU_SHELL'],
          'UKIRYU_FORMAT' => ENV['UKIRYU_FORMAT'],
          'UKIRYU_OUTPUT' => ENV['UKIRYU_OUTPUT'],
          'UKIRYU_USE_COLOR' => ENV['UKIRYU_USE_COLOR']
        }

        has_env = false
        env_vars.each do |k, v|
          if v
            has_env = true
            say "  #{k.ljust(25)}: #{v}", :white
          end
        end
        say '  (none set)', :dim unless has_env
      end

      # Get a configuration value
      #
      # @param key [String] the config key
      def action_get(key)
        normalized_key = normalize_key(key)

        value = case normalized_key
                when :register then config.register
                when :timeout then config.timeout
                when :debug then config.debug
                when :dry_run then config.dry_run
                when :metrics then config.metrics
                when :shell then config.shell
                when :format then config.format
                when :output then config.output
                when :use_color then config.use_color
                else
                  error! "Unknown config key: #{key}\nValid keys: register, timeout, debug, dry_run, metrics, shell, format, output, use_color"
                end

        say "#{key}: #{format_config_value(value, '(not set)')}", :white
      end

      # Set a configuration value (persisted to file)
      #
      # @param key [String] the config key
      # @param value [String] the config value
      def action_set(key, value)
        error! 'Usage: ukiryu config set <key> <value>' unless key && value

        normalized_key = normalize_key(key)
        parsed_value = parse_value(normalized_key, value)

        # Save to persistent config
        ensure_config_dir
        persistent = load_persistent_config || {}
        persistent[key] = value
        save_persistent_config(persistent)

        # Also set in current config
        set_config_value(normalized_key, parsed_value)

        say "Set #{key} = #{value}", :green
        say "Saved to: #{CONFIG_FILE}", :dim
      end

      # Unset a configuration value
      #
      # @param key [String] the config key
      def action_unset(key)
        error! 'Usage: ukiryu config unset <key>' unless key

        persistent = load_persistent_config
        error! "Key not set in persistent config: #{key}" unless persistent&.key?(key)

        persistent.delete(key)
        save_persistent_config(persistent)

        say "Unset #{key}", :green
        say "Updated: #{CONFIG_FILE}", :dim
      end

      # Normalize key to symbol
      #
      # @param key [String] the key
      # @return [Symbol] normalized key
      def normalize_key(key)
        key.to_s.downcase.to_sym
      end

      # Parse value based on key type
      #
      # @param key [Symbol] the config key
      # @param value [String] the string value
      # @return [Object] parsed value
      def parse_value(key, value)
        case key
        when :timeout
          value.to_i
        when :debug, :dry_run, :metrics, :use_color
          %w[true yes 1].include?(value.downcase)
        when :format
          value.to_sym
        else
          value
        end
      end

      # Set config value
      #
      # @param key [Symbol] the config key
      # @param value [Object] the value
      def set_config_value(key, value)
        case key
        when :timeout then config.timeout = value
        when :debug then config.debug = value
        when :dry_run then config.dry_run = value
        when :metrics then config.metrics = value
        when :shell then config.shell = value
        when :format then config.format = value
        when :output then config.output = value
        when :register then config.register = value
        when :use_color then config.use_color = value
        end
      end

      # Format config value for display
      #
      # @param value [Object] the value
      # @param default [String] default string for nil
      # @return [String] formatted value
      def format_config_value(value, default = '(nil)')
        value.nil? ? default : value
      end

      # Format register display showing actual register being used
      #
      # @return [String] formatted register display
      def format_register_display
        register = Ukiryu::Register.default
        info = register.info

        if info[:valid]
          source_label = format_source_label(info[:source])
          tools_count = info[:tools_count] ? " (#{info[:tools_count]} tools)" : ''
          "#{info[:path]} [#{source_label}]#{tools_count}"
        elsif info[:exists]
          "#{info[:path]} (invalid - run: ukiryu register update --force)"
        else
          '~/.ukiryu/register (not found - run: ukiryu register update)'
        end
      rescue Ukiryu::Register::Error
        '~/.ukiryu/register (not found - run: ukiryu register update)'
      end

      # Format source label for display
      #
      # @param source [Symbol] the source symbol
      # @return [String] formatted source label
      def format_source_label(source)
        case source
        when :env
          'env'
        when :user
          'user'
        else
          source.to_s
        end
      end

      # Ensure config directory exists
      def ensure_config_dir
        FileUtils.mkdir_p(CONFIG_DIR) unless Dir.exist?(CONFIG_DIR)
      end

      # Load persistent config from file
      #
      # @return [Hash, nil] the persistent config or nil
      def load_persistent_config
        return nil unless File.exist?(CONFIG_FILE)

        YAML.load_file(CONFIG_FILE, permitted_classes: [Symbol])
      rescue StandardError => e
        say "Warning: Failed to load config file: #{e.message}", :red
        nil
      end

      # Save persistent config to file
      #
      # @param data [Hash] the config data
      def save_persistent_config(data)
        File.write(CONFIG_FILE, data.to_yaml)
      end
    end
  end
end
