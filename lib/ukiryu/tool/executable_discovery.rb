# frozen_string_literal: true

module Ukiryu
  class Tool
    # Executable discovery and inspection
    #
    # Provides methods to find tool executables and discover
    # how they were found (PATH vs shell alias).
    #
    # @api private
    module ExecutableDiscovery
      # Find the executable path using ExecutableLocator
      #
      # Searches for the tool executable by:
      # 1. Checking shell aliases
      # 2. Checking system PATH
      #
      # Sets @executable_info with discovery metadata.
      #
      # @return [String, nil] the executable path or nil if not found
      def find_executable
        result = ::Ukiryu::ExecutableLocator.find_with_info(
          tool_name: @profile.name,
          aliases: @profile.aliases || [],
          platform: @platform
        )
        return nil unless result

        @executable_info = result[:info]
        result[:path]
      end

      # Check if the tool was found via shell alias
      #
      # @return [Boolean] true if executable is a shell alias
      def alias?
        @executable_info&.alias? || false
      end

      # Check if the tool was found in PATH
      #
      # @return [Boolean] true if executable was found in PATH
      def path_found?
        @executable_info&.path? || false
      end

      # Get discovery description
      #
      # @return [String, nil] human-readable description of how tool was found
      def discovery_description
        @executable_info&.description
      end
    end
  end
end
