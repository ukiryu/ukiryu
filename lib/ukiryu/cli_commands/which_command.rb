# frozen_string_literal: true

module Ukiryu
  module CliCommands
    # Show which tool implementation would be selected
    class WhichCommand < BaseCommand
      # Execute the which command
      #
      # @param identifier [String] the tool name, interface, or alias
      def run(identifier)
        setup_register

        runtime = Ukiryu::Runtime.instance
        platform = options[:platform] || runtime.platform
        shell = options[:shell] || runtime.shell

        say '', :clear
        say "Resolving: #{identifier}", :cyan
        say "  Platform: #{platform}", :white
        say "  Shell: #{shell}", :white
        say '', :clear

        # First try exact name match
        tool = try_exact_match(identifier, platform, shell)

        # If not found, try interface/alias discovery
        tool ||= try_interface_discovery(identifier, platform, shell)

        if tool
          show_selected_tool(tool, identifier, platform, shell)
        else
          error! "No tool found for: #{identifier}\nAvailable tools: #{Ukiryu::Register.tools.sort.join(', ')}"
        end
      end

      private

      # Try exact name match
      #
      # @param identifier [String] the tool name
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      # @return [Tool, nil] the tool or nil if not found
      def try_exact_match(identifier, platform, shell)
        tool = Ukiryu::Tool.get(identifier, platform: platform, shell: shell)
        say 'Match type: Exact name match', :green
        tool
      rescue Ukiryu::Errors::ToolNotFoundError
        nil
      end

      # Try interface/alias discovery
      #
      # @param identifier [String] the tool name
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      # @return [Tool, nil] the tool or nil if not found
      def try_interface_discovery(identifier, platform, shell)
        candidates = []

        Ukiryu::Register.tools.each do |tool_name|
          tool_metadata = Ukiryu::Register.load_tool_metadata(tool_name.to_sym)
          next unless tool_metadata

          # Check for interface match using proper comparison (handles string/symbol mismatch)
          interface_match = tool_metadata.implements?(identifier)

          # Check for alias match
          alias_match = tool_metadata.aliases.include?(identifier)

          next unless interface_match || alias_match

          # Check platform compatibility
          profile = find_compatible_profile(tool_metadata, platform, shell)
          next unless profile

          match_type = interface_match ? 'interface' : 'alias'
          candidates << {
            name: tool_name,
            metadata: tool_metadata,
            profile: profile,
            match_type: match_type
          }
        end

        return nil if candidates.empty?

        # Select best candidate (prefer available tools)
        selected = candidates.find do |c|
          Ukiryu::Tool.get(c[:name], platform: platform, shell: shell).available?
        end || candidates.first

        say "Match type: #{selected[:match_type]} match", :green

        Ukiryu::Tool.get(selected[:name], platform: platform, shell: shell)
      end

      # Find compatible profile for platform/shell
      #
      # @param metadata [ToolMetadata] the tool metadata
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      # @return [Hash, nil] compatible profile or nil
      def find_compatible_profile(metadata, platform, shell)
        tool_def = Ukiryu::Tools::Generator.load_tool_definition(metadata.name)
        return nil unless tool_def

        tool_def.compatible_profile(platform: platform, shell: shell)
      end

      # Show selected tool information
      #
      # @param tool [Tool] the selected tool
      # @param identifier [String] the original identifier
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      def show_selected_tool(tool, identifier, _platform, _shell)
        say '', :clear
        say 'Selected tool:', :yellow

        if tool.name != identifier
          say "  Query: #{identifier}", :white
          say "  Resolved to: #{tool.name}", :white
        else
          say "  Tool: #{tool.name}", :white
        end

        # Show implementation info
        say "  Implements: #{tool.profile.implements}", :white if tool.profile.implements

        # Show profile used
        profile = tool.instance_variable_get(:@command_profile)
        if profile
          say "  Profile: #{profile.name || 'default'}", :white

          # Show profile details
          platforms = profile.platforms || ['all']
          shells = profile.shells || ['all']
          say "    Platforms: #{Array(platforms).join(', ')}", :dim
          say "    Shells: #{Array(shells).join(', ')}", :dim
        end

        # Show availability
        say '', :clear
        if tool.available?
          say 'Status: AVAILABLE', :green
          say "  Executable: #{tool.executable}", :white
          detected_version = tool.version
          say "  Version: #{detected_version || 'unknown'}", :white if detected_version
        else
          say 'Status: NOT AVAILABLE', :red
          say '  Tool is not installed or not in PATH', :dim
        end
      end
    end
  end
end
