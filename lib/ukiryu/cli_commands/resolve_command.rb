# frozen_string_literal: true

require_relative 'base_command'
require_relative '../definition/discovery'
require_relative '../definition/version_resolver'

module Ukiryu
  module CliCommands
    # Resolve tool definitions
    #
    # The resolve command shows which definition would be used for a tool.
    class ResolveCommand < BaseCommand
      # Execute the resolve command
      #
      # @param tool_name [String] the tool name to resolve
      # @param version_constraint [String, nil] optional version constraint
      def run(tool_name, version_constraint = nil)
        if tool_name.nil?
          say 'Error: Tool name is required', :red
          say '', :clear
          say 'Usage: ukiryu resolve TOOL [VERSION_CONSTRAINT]', :white
          exit 1
        end

        # Resolve the definition
        resolve_definition(tool_name, version_constraint)
      end

      private

      # Resolve which definition would be used
      #
      # @param tool_name [String] the tool name
      # @param version_constraint [String, nil] optional version constraint
      def resolve_definition(tool_name, version_constraint)
        # Get all available definitions for the tool
        definitions = Ukiryu::Definition::Discovery.definitions_for(tool_name)

        if definitions.empty?
          say "Resolution for: #{tool_name}", :cyan
          say '', :clear
          say "✗ No definitions found for '#{tool_name}'", :red
          say '', :clear
          say 'To see available tools:', :cyan
          say '  ukiryu list', :white
          say '', :clear
          say 'To search for definitions:', :cyan
          say '  ukiryu definitions list', :white
          exit 1
        end

        say "Resolution for: #{tool_name}", :cyan
        say '', :clear

        # Show all available definitions
        say "Available Definitions (#{definitions.size}):", :white
        definitions.each do |metadata|
          priority_icon = priority_icon(metadata.priority)
          say "  #{priority_icon} #{metadata.version} (#{metadata.source_type})", :white
          say "    Path: #{metadata.path}", :dim
          say "    Mtime: #{metadata.mtime}", :dim
          say "    Priority: #{metadata.priority}", :dim
          say '', :clear
        end

        # Determine which definition would be used
        if version_constraint
          # Resolve with version constraint
          available_versions = definitions.map(&:version)
          selected_version = Ukiryu::Definition::VersionResolver.resolve(
            version_constraint,
            available_versions
          )

          if selected_version
            selected_metadata = definitions.find { |d| d.version == selected_version }
            say "Selected Definition (constraint: #{version_constraint}):", :cyan
            say "  ✓ #{selected_metadata.name}/#{selected_metadata.version}", :green
            say "    Source: #{selected_metadata.source_type}", :white
            say "    Path: #{selected_metadata.path}", :white
          else
            say "✗ No version satisfies constraint: #{version_constraint}", :red
            say '', :clear
            say 'Available versions:', :white
            available_versions.each do |v|
              say "  - #{v}", :dim
            end
            exit 1
          end
        else
          # Use highest priority definition
          selected_metadata = definitions.first

          say 'Selected Definition (highest priority):', :cyan
          say "  ✓ #{selected_metadata.name}/#{selected_metadata.version}", :green
          say "    Source: #{selected_metadata.source_type}", :white
          say "    Path: #{selected_metadata.path}", :white
          say "    Priority: #{selected_metadata.priority}", :white
        end

        # Check if definition exists and is valid
        return unless selected_metadata && !selected_metadata.exists?

        say '', :clear
        say '⚠ Warning: Definition file does not exist!', :yellow
      end

      # Get priority icon
      #
      # @param priority [Integer] the priority value
      # @return [String] icon character
      def priority_icon(priority)
        case priority
        when 1 then '★'  # User
        when 2 then '◆'  # Bundled
        when 3 then '■'  # Local system
        when 4 then '□'  # System
        when 5 then '△'  # Register
        else '·'
        end
      end
    end
  end
end
