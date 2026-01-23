# frozen_string_literal: true

require_relative 'type'
require_relative 'shell'

module Ukiryu
  # CommandBuilder module provides shared command building functionality.
  #
  # This module contains methods for building command-line arguments from
  # command definitions and parameters. It is used by both Tool and
  # Tools::Base to eliminate code duplication.
  #
  # @api private
  module CommandBuilder
    # Build command arguments from parameters
    #
    # @param command [Models::CommandDefinition] the command definition
    # @param params [Hash] the parameters hash
    # @return [Array<String>] the formatted command arguments
    def build_args(command, params)
      args = []

      # Add subcommand prefix if present (e.g., for ImageMagick "magick convert")
      args << command.subcommand if command.subcommand

      # Add options first (before arguments)
      command.options&.each do |opt_def|
        param_key = opt_def.name_sym
        next unless params.key?(param_key)
        next if params[param_key].nil?

        formatted_opt = format_option(opt_def, params[param_key])
        Array(formatted_opt).each { |opt| args << opt unless opt.nil? || opt.empty? }
      end

      # Add flags
      command.flags&.each do |flag_def|
        param_key = flag_def.name_sym
        value = params[param_key]
        value = flag_def.default if value.nil?

        formatted_flag = format_flag(flag_def, value)
        Array(formatted_flag).each { |flag| args << flag unless flag.nil? || flag.empty? }
      end

      # Separate "last" positioned argument from other arguments
      arguments = command.arguments || []
      last_arg = arguments.find(&:last?)
      regular_args = arguments.reject(&:last?)

      # Add regular positional arguments (in order, excluding "last")
      regular_args.sort_by(&:numeric_position).each do |arg_def|
        param_key = arg_def.name_sym
        next unless params.key?(param_key)

        value = params[param_key]
        next if value.nil?

        if arg_def.variadic
          # Variadic argument - expand array
          array = Type.validate(value, :array, arg_def)
          array.each { |v| args << format_arg(v, arg_def) }
        else
          args << format_arg(value, arg_def)
        end
      end

      # Add post_options (options that come before the "last" argument)
      command.post_options&.each do |opt_def|
        param_key = opt_def.name_sym
        next unless params.key?(param_key)
        next if params[param_key].nil?

        formatted_opt = format_option(opt_def, params[param_key])
        Array(formatted_opt).each { |opt| args << opt unless opt.nil? || opt.empty? }
      end

      # Add the "last" positioned argument (typically output file)
      if last_arg
        param_key = last_arg.name_sym
        if params.key?(param_key) && !params[param_key].nil?
          if last_arg.variadic
            array = Type.validate(params[param_key], :array, last_arg)
            array.each { |v| args << format_arg(v, last_arg) }
          else
            args << format_arg(params[param_key], last_arg)
          end
        end
      end

      args
    end

    # Format a positional argument
    #
    # @param value [Object] the argument value
    # @param arg_def [Models::ArgumentDefinition] the argument definition
    # @return [String] the formatted argument
    def format_arg(value, arg_def)
      # Validate type
      Type.validate(value, arg_def.type || :string, arg_def)

      # Apply platform-specific path formatting
      if arg_def.type == :file
        shell_class = Shell.class_for(@shell)
        shell_class.new.format_path(value.to_s)
      else
        value.to_s
      end
    end

    # Format an option
    #
    # @param opt_def [Models::OptionDefinition] the option definition
    # @param value [Object] the option value
    # @return [String, Array<String>] the formatted option(s)
    def format_option(opt_def, value)
      # Validate type
      Type.validate(value, opt_def.type || :string, opt_def)

      # Handle boolean types - just return the CLI flag (no value)
      type_val = opt_def.type
      if [:boolean, TrueClass, 'boolean'].include?(type_val)
        return nil if value.nil? || value == false

        return opt_def.cli || ''
      end

      cli = opt_def.cli || ''
      format_sym = opt_def.format_sym
      separator = opt_def.separator || '='

      # Convert value to string (handle symbols)
      value_str = value.is_a?(Symbol) ? value.to_s : value.to_s

      # Handle array values with separator
      if value.is_a?(Array) && separator
        joined = value.join(separator)
        case format_sym
        when :double_dash_equals
          "#{cli}#{joined}"
        when :double_dash_space, :single_dash_space
          [cli, joined] # Return array for space-separated
        when :single_dash_equals
          "#{cli}#{joined}"
        else
          "#{cli}#{joined}"
        end
      else
        case format_sym
        when :double_dash_equals
          "#{cli}#{separator}#{value_str}"
        when :double_dash_space, :single_dash_space
          [cli, value_str] # Return array for space-separated
        when :single_dash_equals
          "#{cli}#{separator}#{value_str}"
        when :slash_colon
          "#{cli}:#{value_str}"
        when :slash_space
          "#{cli} #{value_str}"
        else
          "#{cli}#{separator}#{value_str}"
        end
      end
    end

    # Format a flag
    #
    # @param flag_def [Models::FlagDefinition] the flag definition
    # @param value [Object] the flag value
    # @return [String, nil] the formatted flag
    def format_flag(flag_def, value)
      return nil if value.nil? || value == false

      flag_def.cli || ''
    end

    # Build environment variables for command
    #
    # @param command [Models::CommandDefinition] the command definition
    # @param params [Hash] the parameters hash
    # @return [Hash] the environment variables hash
    def build_env_vars(command, params)
      env_vars = {}

      command.env_vars&.each do |ev|
        # Check platform restriction
        platforms = ev.platforms || []
        next if platforms.any? && !platforms.map(&:to_sym).include?(@platform)

        # Get value - use ev.value if provided, or extract from params
        value = if ev.value
                  ev.value
                elsif ev.env_var
                  params[ev.env_var.to_sym]
                end

        # Set the environment variable if value is defined (including empty string)
        env_vars[ev.name] = value.to_s unless value.nil?
      end

      env_vars
    end
  end
end
