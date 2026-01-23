# frozen_string_literal: true

module Ukiryu
  module Execution
    # Execution command information
    #
    # Encapsulates details about the executed command
    class CommandInfo
      attr_reader :executable, :arguments, :full_command, :shell, :tool_name, :command_name

      def initialize(executable:, arguments:, full_command:, shell: nil, tool_name: nil, command_name: nil)
        @executable = executable
        @arguments = arguments
        @full_command = full_command
        @shell = shell
        @tool_name = tool_name
        @command_name = command_name
      end

      # Get the executable name only
      #
      # @return [String] executable name
      def executable_name
        File.basename(@executable)
      end

      # Get argument count
      #
      # @return [Integer] number of arguments
      def argument_count
        @arguments.count
      end

      # String representation
      #
      # @return [String] command string
      def to_s
        @full_command
      end

      # Inspect
      #
      # @return [String] inspection string
      def inspect
        "#<Ukiryu::Execution::CommandInfo exe=#{executable_name.inspect} args=#{argument_count}>"
      end

      # Convert to hash
      #
      # @return [Hash] command info as hash
      def to_h
        {
          executable: @executable,
          executable_name: executable_name,
          tool_name: @tool_name,
          command_name: @command_name,
          arguments: @arguments,
          full_command: @full_command,
          shell: @shell
        }
      end
    end
  end
end
