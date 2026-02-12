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
        # Use executable_name from command profile, falling back to profile name
        executable_name = @command_profile.executable_name || @profile.name

        # Debug logging for executable discovery
        Logger.debug("Tool: #{@profile.name}", category: :executable)
        Logger.debug("Command profile executable_name: #{@command_profile.executable_name.inspect}",
                     category: :executable)
        Logger.debug("Profile name: #{@profile.name.inspect}", category: :executable)
        Logger.debug("Resolved executable_name: #{executable_name.inspect}", category: :executable)
        Logger.debug("Profile aliases: #{@profile.aliases.inspect}", category: :executable)
        Logger.debug("Shell: #{@shell.inspect}", category: :executable)
        Logger.debug("Platform: #{@platform.inspect}", category: :executable)

        result = ::Ukiryu::ExecutableLocator.find_with_info(
          tool_name: executable_name,
          aliases: @profile.aliases || [],
          platform: @platform
        )

        if result
          Logger.debug("Found executable: #{result[:path]}", category: :executable)
          Logger.debug("Discovery source: #{result[:info].source.inspect}", category: :executable)
        else
          Logger.debug('EXECUTABLE NOT FOUND!', category: :executable)
        end

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
