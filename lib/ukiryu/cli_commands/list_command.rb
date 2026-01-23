# frozen_string_literal: true

require_relative 'base_command'
require_relative '../tool'
require_relative '../registry'

module Ukiryu
  module CliCommands
    # List all available tools in the registry
    class ListCommand < BaseCommand
      # Execute the list command
      def run
        setup_registry

        tools = Registry.tools
        error! 'No tools found in registry' if tools.empty?

        say "Available tools (#{tools.count}):", :cyan

        # Separate tools into interfaces and standalone tools
        interfaces = {}
        standalone_tools = []

        tools.sort.each do |name|
          metadata = Registry.load_tool_metadata(name.to_sym)

          if metadata&.implements
            # This tool implements an interface
            interface_name = metadata.implements.to_s
            interfaces[interface_name] ||= []
            interfaces[interface_name] << name
          elsif metadata&.aliases&.any?
            # Tool has aliases but doesn't implement interface - treat as standalone
            standalone_tools << name
          else
            # Regular standalone tool
            standalone_tools << name
          end
        rescue Ukiryu::Error
          # If we can't load metadata, treat as standalone
          standalone_tools << name
        end

        # Display interfaces first
        interfaces.sort.each do |interface_name, impls|
          say "  #{interface_name}:", :cyan

          impls.sort.each do |impl_name|
            tool = Tool.get(impl_name)
            version_info = tool.version ? "v#{tool.version}" : 'version unknown'
            available = tool.available? ? '[✓]' : '[✗]'
            say "    #{available.ljust(4)} #{impl_name.ljust(20)} #{version_info}", tool.available? ? :green : :red
          rescue Ukiryu::Error => e
            say "    [?] #{impl_name.ljust(20)} error: #{e.message}", :red
          end
        end

        # Display standalone tools
        standalone_tools.sort.each do |name|
          tool = Tool.get(name)
          version_info = tool.version ? "v#{tool.version}" : 'version unknown'
          available = tool.available? ? '[✓]' : '[✗]'
          say "  #{available.ljust(4)} #{name.ljust(20)} #{version_info}", tool.available? ? :green : :red
        rescue Ukiryu::Error => e
          say "  [?] #{name.ljust(20)} error: #{e.message}", :red
        end
      end
    end
  end
end
