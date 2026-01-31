# frozen_string_literal: true

module Ukiryu
  module Tools
    # Executable finder utilities for tool classes
    #
    # This module provides methods to find executables on the system
    # using aliases from tool definitions and system PATH.
    module ExecutableFinder
      # Find the executable for a tool
      #
      # @param tool_name [String] the tool name
      # @param tool_definition [Models::ToolDefinition] the tool definition
      # @return [String, nil] path to executable or nil
      def self.find_executable(tool_name, tool_definition)
        platform = Ukiryu::Runtime.instance.platform

        Ukiryu::ExecutableLocator.find(
          tool_name: tool_name,
          aliases: tool_definition.aliases || [],
          platform: platform
        )
      end
    end
  end
end
