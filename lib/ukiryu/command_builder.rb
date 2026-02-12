# frozen_string_literal: true

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

      # Debug logging for CI - log all params
      Logger.debug("command: #{command.name}", category: :executable)
      Logger.debug("params: #{params.inspect}", category: :executable)
      Logger.debug("params.class: #{params.class}", category: :executable)

      # Add subcommand prefix if present (e.g., for ImageMagick "magick convert")
      args << command.subcommand if command.subcommand

      # Add prefix flags FIRST (must come before any options)
      command.flags&.each do |flag_def|
        param_key = flag_def.name_sym
        next unless flag_def.position_constraint_sym == :prefix

        value = params[param_key]
        value = flag_def.default if value.nil?

        formatted_flag = format_flag(flag_def, value)
        Array(formatted_flag).each { |flag| args << flag unless flag.nil? || flag.empty? }
      end

      # Add options (after prefix flags)
      command.options&.each do |opt_def|
        param_key = opt_def.name_sym
        next unless params.key?(param_key)
        next if params[param_key].nil?

        formatted_opt = format_option(opt_def, params[param_key])

        # Debug logging
        Logger.debug("formatted_opt for #{param_key}: #{formatted_opt.inspect}",
                     category: :executable)

        Array(formatted_opt).each { |opt| args << opt unless opt.nil? || opt.empty? }
      end

      # Add non-prefix flags (after options)
      command.flags&.each do |flag_def|
        param_key = flag_def.name_sym
        next if flag_def.position_constraint_sym == :prefix

        value = params[param_key]
        value = flag_def.default if value.nil?

        formatted_flag = format_flag(flag_def, value)
        Array(formatted_flag).each { |flag| args << flag unless flag.nil? || flag.empty? }
      end

      # Separate "last" positioned argument from other arguments
      arguments = command.arguments || []
      last_arg = arguments.find(&:last?)
      regular_args = arguments.reject(&:last?)

      # Debug logging for arguments
      Logger.debug("arguments: #{arguments.inspect}", category: :executable)
      Logger.debug("regular_args: #{regular_args.map(&:name_sym).inspect}",
                   category: :executable)
      Logger.debug("last_arg: #{last_arg&.name_sym.inspect}", category: :executable)

      # Add regular positional arguments (in order, excluding "last")
      regular_args.sort_by(&:numeric_position).each do |arg_def|
        param_key = arg_def.name_sym
        next unless params.key?(param_key)

        value = params[param_key]
        next if value.nil?

        # Debug logging
        Logger.debug("param_key: #{param_key.inspect}", category: :executable)
        Logger.debug("value.class: #{value.class}", category: :executable)
        Logger.debug("value.inspect: #{value.inspect}", category: :executable)
        Logger.debug("arg_def.variadic: #{arg_def.variadic}", category: :executable)

        if arg_def.variadic
          # Variadic argument - expand array
          array = Ukiryu::Type.validate(value, :array, arg_def)
          Logger.debug("array.class: #{array.class}", category: :executable)
          Logger.debug("array.inspect: #{array.inspect}", category: :executable)
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
            array = Ukiryu::Type.validate(params[param_key], :array, last_arg)
            array.each { |v| args << format_arg(v, last_arg) }
          else
            args << format_arg(params[param_key], last_arg)
          end
        end
      end

      # Debug logging for final args
      Logger.debug("Final args: #{args.inspect}", category: :executable)
      Logger.debug("Args class: #{args.class}", category: :executable)
      Logger.debug("Args size: #{args.size}", category: :executable)
      args.each_with_index do |arg, i|
        Logger.debug("args[#{i}]: #{arg.inspect} (#{arg.class})", category: :executable)
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
      Ukiryu::Type.validate(value, arg_def.type || :string, arg_def)

      # Apply platform-specific path formatting
      if arg_def.type.to_s == 'file'
        shell = Ukiryu::Shell::InstanceCache.instance_for(@shell)
        shell.format_path(value.to_s)
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
      Ukiryu::Type.validate(value, opt_def.type || :string, opt_def)

      # Debug logging - trace the full option formatting
      Logger.debug("opt_def.name: #{opt_def.name.inspect}", category: :executable)
      Logger.debug("opt_def.cli: #{opt_def.cli.inspect}", category: :executable)
      Logger.debug("opt_def.assignment_delimiter: #{opt_def.assignment_delimiter.inspect}",
                   category: :executable)
      Logger.debug("value: #{value.inspect} (#{value.class})", category: :executable)

      # Handle boolean types - just return the CLI flag (no value)
      type_val = opt_def.type
      if [:boolean, TrueClass, 'boolean'].include?(type_val)
        return nil if value.nil? || value == false

        return opt_def.cli || ''
      end

      cli = opt_def.cli || ''
      delimiter_sym = opt_def.assignment_delimiter_sym
      separator = opt_def.separator || '='

      Logger.debug("cli variable: #{cli.inspect}", category: :executable)
      Logger.debug("delimiter_sym: #{delimiter_sym.inspect}", category: :executable)

      # Auto-detect delimiter based on CLI prefix
      delimiter_sym = detect_delimiter(cli) if delimiter_sym == :auto

      Logger.debug("delimiter_sym after detect: #{delimiter_sym.inspect}",
                   category: :executable)

      # Convert value to string (handle symbols and file paths)
      if value.is_a?(Symbol)
        value_str = value.to_s
      elsif opt_def.type.to_s == 'file'
        # Apply platform-specific path formatting for file types
        shell_instance = Ukiryu::Shell::InstanceCache.instance_for(@shell)
        Logger.debug("FILE type detected: opt_def.name=#{opt_def.name}, value=#{value.inspect}",
                     category: :executable)
        Logger.debug("@shell=#{@shell.inspect}, shell_instance=#{shell_instance.class}",
                     category: :executable)
        Logger.debug("Platform.windows?=#{Ukiryu::Platform.windows? if defined?(Ukiryu::Platform)}",
                     category: :executable)
        value_str = shell_instance.format_path(value.to_s)
        Logger.debug("format_path result: #{value_str.inspect}", category: :executable)
      else
        value_str = value.to_s
      end

      # Handle array values with separator
      if value.is_a?(Array) && separator
        # Apply path formatting to each element if type is file
        formatted_values = if opt_def.type.to_s == 'file'
                             shell_instance ||= Ukiryu::Shell::InstanceCache.instance_for(@shell)
                             value.map { |v| shell_instance.format_path(v.to_s) }
                           else
                             value.map(&:to_s)
                           end
        joined = formatted_values.join(separator)
        result = case delimiter_sym
                 when :equals
                   "#{cli}=#{joined}"
                 when :space
                   [cli, joined] # Return array for space-separated
                 when :colon
                   "#{cli}:#{joined}"
                 when :none
                   cli
                 else
                   "#{cli}=#{joined}"
                 end
      else
        result = case delimiter_sym
                 when :equals
                   "#{cli}=#{value_str}"
                 when :space
                   [cli, value_str] # Return array for space-separated
                 when :colon
                   "#{cli}:#{value_str}"
                 when :none
                   cli
                 else
                   "#{cli}=#{value_str}"
                 end
      end

      # Debug logging for result
      Logger.debug("FINAL result: #{result.inspect}", category: :executable)
      Logger.debug("result.class: #{result.class}", category: :executable)

      result
    end

    # Detect assignment delimiter based on CLI prefix
    #
    # @param cli [String] the CLI flag
    # @return [Symbol] the delimiter
    def detect_delimiter(cli)
      case cli
      when /^--/ then :equals   # --flag=value
      when /^-/ then :space     # -f value
      when %r{^/} then :colon # /format:value
      else :equals
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
    # @param profile [Models::PlatformProfile] the profile (for env_var_sets)
    # @param params [Hash] the parameters hash
    # @return [Hash] the environment variables hash
    def build_env_vars(command, profile, params)
      env_vars = {}

      # First, add env vars from sets specified in use_env_vars
      command.use_env_vars&.each do |set_name|
        set = profile.env_var_sets&.dig(set_name.to_s)
        next unless set

        set.each do |ev_data|
          # Convert hash to EnvVarDefinition if needed
          ev = ev_data.is_a?(Hash) ? Models::EnvVarDefinition.new(ev_data) : ev_data

          # Check platform restriction
          platforms = ev.platforms || []
          next if platforms.any? && !platforms.map(&:to_sym).include?(@platform)

          # Get value - use ev.value if provided, or extract from params
          value = if ev.value
                    ev.value
                  elsif ev.from
                    params[ev.from.to_sym]
                  end

          # Set the environment variable if value is defined (including empty string)
          env_vars[ev.name] = value.to_s unless value.nil?
        end
      end

      # Then, add command's own env_vars (can override set values)
      command.env_vars&.each do |ev|
        # Check platform restriction
        platforms = ev.platforms || []
        next if platforms.any? && !platforms.map(&:to_sym).include?(@platform)

        # Get value - use ev.value if provided, or extract from params
        value = if ev.value
                  ev.value
                elsif ev.from
                  params[ev.from.to_sym]
                end

        # Set the environment variable if value is defined (including empty string)
        env_vars[ev.name] = value.to_s unless value.nil?
      end

      env_vars
    end
  end
end
