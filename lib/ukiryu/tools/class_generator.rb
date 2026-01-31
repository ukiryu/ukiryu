# frozen_string_literal: true

module Ukiryu
  module Tools
    # Class generation utilities for tool-specific classes
    #
    # This module handles the dynamic generation of Options, Action, and Response
    # classes for each tool command, keeping the Base class focused on execution.
    module ClassGenerator
      # Generate an options class for a command
      #
      # @param tool_class [Class] the tool class
      # @param command_name [Symbol] the command name
      # @param command_def [Models::CommandDefinition] the command definition
      # @return [Class] the generated options class
      def self.generate_options_class(tool_class, command_name, command_def)
        # Capture tool class in closure
        tool_class_ref = tool_class

        # Create class name
        class_name = "#{command_name.to_s.capitalize}Options"

        # Define the class in the tool's namespace
        options_class = Class.new(::Ukiryu::Options::Base) do
          # Store command definition
          @command_def = command_def
          @command_name = command_name
          @tool_class = tool_class_ref

          # Class methods
          singleton_class.send(:define_method, :command_def) do
            @command_def
          end

          singleton_class.send(:define_method, :command_name) do
            @command_name
          end

          singleton_class.send(:define_method, :tool_class) do
            @tool_class
          end
        end

        # Define accessors using the OptionsBuilder
        Ukiryu::OptionsBuilder.define_accessors(options_class, command_def)
        Ukiryu::OptionsBuilder.define_to_shell_method(options_class, command_def)
        Ukiryu::OptionsBuilder.define_validation_method(options_class, command_def)

        # Define extra_args accessor for manual option injection
        options_class.send(:attr_accessor, :extra_args)

        # Define set() method for batch assignment
        options_class.send(:define_method, :set) do |params|
          params.each do |key, value|
            setter = "#{key}="
            send(setter, value) if respond_to?(setter)
          end
          self
        end

        # Define run() method that executes on the associated tool
        options_class.send(:define_method, :run) do
          # Validate options before execution
          validate!
          tool_instance = tool_class_ref.new
          tool_instance.execute(command_name, self)
        end

        # Const the class in the tool's namespace
        tool_class_ref.const_set(class_name, options_class) unless tool_class_ref.const_defined?(class_name)

        options_class
      end

      # Generate an action class for a command
      #
      # @param tool_class [Class] the tool class
      # @param command_name [Symbol] the command name
      # @param command_def [Models::CommandDefinition] the command definition
      # @return [Class] the generated action class
      def self.generate_action_class(tool_class, command_name, command_def)
        class_name = "#{command_name.to_s.capitalize}Action"

        action_class = Class.new(::Ukiryu::Action::Base) do
          @command_name = command_name
          @command_def = command_def
          @tool_class = tool_class

          singleton_class.send(:define_method, :command_name) do
            @command_name
          end

          singleton_class.send(:define_method, :command_def) do
            @command_def
          end

          singleton_class.send(:define_method, :tool_class) do
            @tool_class
          end
        end

        tool_class.const_set(class_name, action_class) unless tool_class.const_defined?(class_name)
        action_class
      end

      # Generate a response class for a command
      #
      # @param tool_class [Class] the tool class
      # @param command_name [Symbol] the command name
      # @param command_def [Models::CommandDefinition] the command definition
      # @return [Class] the generated response class
      def self.generate_response_class(tool_class, command_name, command_def)
        class_name = "#{command_name.to_s.capitalize}Response"

        response_class = Class.new(::Ukiryu::Response::Base) do
          @command_name = command_name
          @command_def = command_def
        end

        tool_class.const_set(class_name, response_class) unless tool_class.const_defined?(class_name)
        response_class
      end
    end
  end
end
