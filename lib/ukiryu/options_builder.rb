# frozen_string_literal: true

require_relative 'shell'
require_relative 'type'
require_relative 'cache'
require_relative 'options_builder/formatter'
require_relative 'options_builder/validator'

module Ukiryu
  # Builds structured option classes from tool profile metadata
  #
  # This module dynamically creates option classes based on YAML profile definitions,
  # providing type-safe option building with shell serialization capabilities.
  #
  # @example
  #   # Get options class for a command
  #   options_class = Ukiryu::OptionsBuilder.for(:imagemagick, :convert)
  #   options = options_class.new
  #   options.inputs = ["input.png"]
  #   options.output = "output.jpg"
  #   options.resize = "50x50"
  #
  #   # Serialize to shell command
  #   shell_args = options.to_shell(type: :bash)
  module OptionsBuilder
    class << self
      # Get the options classes cache (bounded LRU cache)
      #
      # @return [Cache] the options classes cache
      def option_classes_cache
        @option_classes_cache ||= Cache.new(max_size: 100, ttl: 3600)
      end

      # Get or create an options class for a tool command
      #
      # @param tool_name [String, Symbol] the tool name
      # @param command_name [String, Symbol] the command name
      # @return [Class] the dynamically generated options class
      def for(tool_name, command_name)
        tool_name_sym = tool_name.to_sym
        command_name_sym = command_name.to_sym

        # Check if we've already created this class
        cache_key = [tool_name_sym, command_name_sym]
        cached = option_classes_cache[cache_key]
        return cached if cached

        # Get the tool and command profile
        tool = Tool.get(tool_name_sym)
        command_def = tool.command_definition(command_name_sym)

        raise ArgumentError, "Unknown command: #{command_name} for tool: #{tool_name}" unless command_def

        # Create the options class
        options_class = create_options_class(tool_name_sym, command_name_sym, command_def)
        option_classes_cache[cache_key] = options_class
        options_class
      end

      # Clear the options class cache (mainly for testing)
      #
      # @api private
      def clear_cache
        option_classes_cache.clear
      end

      # Convert an options object to a hash for backward compatibility
      #
      # @param options [Object] an options object created by the options class
      # @return [Hash] the options as a hash
      def to_hash(options)
        hash = {}

        # Get the command definition from the options class
        command_def = options.class.command_def
        return {} unless command_def

        # Extract all argument values
        (command_def.arguments || []).each do |arg_def|
          attr_name = arg_def.name
          value = options.send(attr_name)
          hash[attr_name.to_sym] = value unless value.nil?
        end

        # Extract all option values
        (command_def.options || []).each do |opt_def|
          attr_name = opt_def.name
          value = options.send(attr_name)
          hash[attr_name.to_sym] = value unless value.nil?
        end

        # Extract all flag values
        (command_def.flags || []).each do |flag_def|
          attr_name = flag_def.name
          value = options.send(attr_name)
          # Only include flags that are true
          hash[attr_name.to_sym] = value if value
        end

        # Extract all post_option values
        (command_def.post_options || []).each do |opt_def|
          attr_name = opt_def.name
          value = options.send(attr_name)
          hash[attr_name.to_sym] = value unless value.nil?
        end

        # Include extra_args if present (for manual option injection)
        hash[:extra_args] = options.extra_args if options.respond_to?(:extra_args) && !options.extra_args.nil?

        hash
      end

      # Create a dynamic options class from command definition
      #
      # @param tool_name [Symbol] the tool name
      # @param command_name [Symbol] the command name
      # @param command_def [Hash] the command definition from profile
      # @return [Class] the generated options class
      def create_options_class(tool_name, command_name, command_def)
        # Capture values in closure for singleton methods
        cmd_def = command_def
        t_name = tool_name
        c_name = command_name

        Class.new do
          # Define class methods with closure access
          singleton_class.send(:define_method, :command_def) do
            cmd_def
          end

          singleton_class.send(:define_method, :tool_name) do
            t_name
          end

          singleton_class.send(:define_method, :command_name) do
            c_name
          end

          # Define attribute accessors for each argument and option
          OptionsBuilder.define_accessors(self, command_def)

          # Define to_shell method for serialization
          OptionsBuilder.define_to_shell_method(self, command_def)

          # Define validation method
          OptionsBuilder::Validator.define_validation_method(self, command_def)
        end
      end

      # Define attribute accessors for arguments and options
      #
      # @param klass [Class] the class to define accessors on
      # @param command_def [CommandDefinition] the command definition
      def define_accessors(klass, command_def)
        # Define accessors for arguments
        (command_def.arguments || []).each do |arg_def|
          attr_name = arg_def.name
          # Create getter and setter
          klass.define_method(attr_name) do
            instance_variable_get("@#{attr_name}")
          end

          klass.define_method("#{attr_name}=") do |value|
            # For variadic arguments, validate each element
            validated = if arg_def.variadic && value.is_a?(Array)
                          value.map { |v| Type.validate(v, arg_def.type || :string, arg_def) }
                        else
                          Type.validate(value, arg_def.type || :string, arg_def)
                        end
            instance_variable_set("@#{attr_name}", validated)
          end
        end

        # Define accessors for options
        (command_def.options || []).each do |opt_def|
          attr_name = opt_def.name
          klass.define_method(attr_name) do
            instance_variable_get("@#{attr_name}")
          end

          klass.define_method("#{attr_name}=") do |value|
            # Skip if nil (optional option not set)
            return if value.nil?

            # Validate and coerce the value
            validated = Type.validate(value, opt_def.type || :string, opt_def)
            instance_variable_set("@#{attr_name}", validated)
          end
        end

        # Define accessors for flags
        (command_def.flags || []).each do |flag_def|
          attr_name = flag_def.name
          klass.define_method(attr_name) do
            instance_variable_get("@#{attr_name}")
          end

          klass.define_method("#{attr_name}=") do |value|
            instance_variable_set("@#{attr_name}", !!value)
          end
        end

        # Define accessors for post_options
        (command_def.post_options || []).each do |opt_def|
          attr_name = opt_def.name
          klass.define_method(attr_name) do
            instance_variable_get("@#{attr_name}")
          end

          klass.define_method("#{attr_name}=") do |value|
            return if value.nil?

            validated = Type.validate(value, opt_def.type || :string, opt_def)
            instance_variable_set("@#{attr_name}", validated)
          end
        end
      end

      # Define to_shell method for command serialization
      #
      # @param klass [Class] the class to define the method on
      # @param command_def [CommandDefinition] the command definition
      def define_to_shell_method(klass, command_def)
        klass.define_method(:to_shell) do |shell_type: :bash|
          shell_type = shell_type.to_sym
          shell_class = Shell.class_for(shell_type)
          shell_instance = shell_class.new

          args = []

          # Add subcommand if present
          args << command_def.subcommand if command_def.subcommand

          # Add options (before arguments)
          (command_def.options || []).each do |opt_def|
            attr_name = opt_def.name
            value = instance_variable_get("@#{attr_name}")
            next if value.nil? # Skip unset options

            formatted = Formatter.format_option(opt_def, value, shell_instance)
            Array(formatted).each { |a| args << a unless a.nil? || a.empty? }
          end

          # Add flags
          (command_def.flags || []).each do |flag_def|
            attr_name = flag_def.name
            value = instance_variable_get("@#{attr_name}")

            # Use default if not set
            value = flag_def.default if value.nil?
            next unless value

            formatted = Formatter.format_flag(flag_def, shell_instance)
            Array(formatted).each { |f| args << f unless f.nil? || f.empty? }
          end

          # Separate "last" positioned argument from other arguments
          arguments = command_def.arguments || []
          last_arg = arguments.find { |a| ['last', :last].include?(a.position) }
          regular_args = arguments.reject { |a| ['last', :last].include?(a.position) }

          # Add regular positional arguments (in order)
          regular_args.sort_by do |a|
            pos = a.position
            pos.is_a?(Integer) ? pos : (pos || 99)
          end.each do |arg_def|
            attr_name = arg_def.name
            value = instance_variable_get("@#{attr_name}")
            next if value.nil?

            if arg_def.variadic
              Array(value).each do |v|
                args << Formatter.format_arg(v, arg_def, shell_instance)
              end
            else
              args << Formatter.format_arg(value, arg_def, shell_instance)
            end
          end

          # Add post_options (between regular args and last arg)
          (command_def.post_options || []).each do |opt_def|
            attr_name = opt_def.name
            value = instance_variable_get("@#{attr_name}")
            next if value.nil?

            formatted = Formatter.format_option(opt_def, value, shell_instance)
            Array(formatted).each { |a| args << a unless a.nil? || a.empty? }
          end

          # Add the "last" positioned argument (typically output)
          if last_arg
            attr_name = last_arg.name
            value = instance_variable_get("@#{attr_name}")
            if value
              if last_arg.variadic
                Array(value).each do |v|
                  args << Formatter.format_arg(v, last_arg, shell_instance)
                end
              else
                args << Formatter.format_arg(value, last_arg, shell_instance)
              end
            end
          end

          # Join into command string
          shell_instance.join(*args)
        end
      end
    end
  end
end
