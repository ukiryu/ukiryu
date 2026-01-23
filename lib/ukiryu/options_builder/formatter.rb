# frozen_string_literal: true

require_relative '../shell'

module Ukiryu
  module OptionsBuilder
    # Formatting utilities for options, flags, and arguments
    #
    # This module handles the conversion of option values into shell command
    # arguments according to various format styles.
    module Formatter
      # Format an option according to its definition
      #
      # @param opt_def [OptionDefinition] the option definition
      # @param value [Object] the value to format
      # @param shell_instance [Shell::Base] the shell instance
      # @return [String, Array<String>] the formatted option(s)
      def self.format_option(opt_def, value, _shell_instance)
        type = opt_def.type

        # Handle boolean types - just return the CLI flag
        if [:boolean, TrueClass, 'boolean'].include?(type)
          return nil if value.nil? || value == false

          return opt_def.cli || ''
        end

        cli = opt_def.cli || ''
        format = opt_def.format || 'double_dash_equals'
        format_sym = format.is_a?(String) ? format.to_sym : format

        value_str = value.is_a?(Symbol) ? value.to_s : value.to_s

        # Handle array values
        if value.is_a?(Array) && opt_def.separator
          joined = value.join(opt_def.separator)
          return case format_sym
                 when :double_dash_equals
                   "#{cli}#{joined}"
                 when :double_dash_space, :single_dash_space
                   [cli, joined]
                 else
                   "#{cli}#{joined}"
                 end
        end

        case format_sym
        when :double_dash_equals
          "#{cli}=#{value_str}"
        when :double_dash_space, :single_dash_space
          [cli, value_str]
        when :single_dash_equals
          "#{cli}=#{value_str}"
        when :slash_colon
          "#{cli}:#{value_str}"
        when :slash_space
          "#{cli} #{value_str}"
        else
          "#{cli}=#{value_str}"
        end
      end

      # Format a flag according to its definition
      #
      # @param flag_def [FlagDefinition] the flag definition
      # @param shell_instance [Shell::Base] the shell instance
      # @return [String, nil] the formatted flag
      def self.format_flag(flag_def, _shell_instance)
        flag_def.cli || ''
      end

      # Format an argument value
      #
      # @param value [Object] the value to format
      # @param arg_def [ArgumentDefinition] the argument definition
      # @param shell_instance [Shell::Base] the shell instance
      # @return [String] the formatted argument
      def self.format_arg(value, arg_def, shell_instance)
        if arg_def.type == :file
          shell_instance.format_path(value.to_s)
        else
          value.to_s
        end
      end
    end
  end
end
