# frozen_string_literal: true

module Ukiryu
  module Action
    # Abstract base class for action classes
    #
    # Action classes represent executable commands and provide a fluent
    # interface for building and executing commands.
    #
    # This is an alternative pattern to using options objects directly.
    #
    # @abstract
    class Base
      class << self
        # Get the command name
        #
        # @return [Symbol] the command name
        attr_reader :command_name

        # Get the command definition
        #
        # @return [Hash] the command definition
        attr_reader :command_def

        # Get the associated tool class
        #
        # @return [Class] the tool class
        attr_reader :tool_class
      end

      # Create a new action
      #
      # @param tool_instance [Tools::Base] the tool instance to use
      def initialize(tool_instance = nil)
        @tool = tool_instance || self.class.tool_class.new
      end

      # Execute this action with options
      #
      # @param options [Hash, Options::Base] the options to use
      # @param timeout [Integer] timeout in seconds (required)
      # @return [Response::Base] the execution response
      def run(options = {}, timeout:)
        # If options is a hash, create an options object
        if options.is_a?(Hash)
          options_class = @tool.options_class_for(self.class.command_name)
          options_obj = options_class.new
          options_obj.set(options)
          options = options_obj
        end

        # Execute with the tool
        @tool.execute(self.class.command_name, options, timeout: timeout)
      end

      # Create an options object for this action
      #
      # @return [Options::Base] a new options object
      def options
        @tool.options_class_for(self.class.command_name).new
      end

      # Get the command name
      #
      # @return [Symbol] the command name
      def command_name
        self.class.command_name
      end

      # Get the command definition
      #
      # @return [Hash] the command definition
      def command_def
        self.class.command_def
      end
    end
  end
end
