# frozen_string_literal: true

require_relative 'base_command'
require_relative '../tool'

module Ukiryu
  module CliCommands
    # Show detailed information about a tool
    class InfoCommand < BaseCommand
      # Execute the info command
      #
      # @param tool_name [String] the tool name
      def run(tool_name)
        setup_registry

        # Use find_by for interface-based discovery (ping -> ping_bsd/ping_gnu)
        tool = Tool.find_by(tool_name.to_sym)
        error!("Tool not found: #{tool_name}\nAvailable tools: #{Registry.tools.sort.join(', ')}") unless tool

        profile = tool.profile
        show_all = options[:all]

        say '', :clear

        # Show interface information if queried name differs from actual tool name
        if profile.name != tool_name.to_s && profile.implements
          say "Interface: #{tool_name}", :cyan
          say "  This tool implements the '#{tool_name}' interface", :dim
          say "  Tool: #{profile.name}", :white

          # Find other implementations of this interface
          other_implementations = find_other_implementations(tool_name.to_s, profile.name)
          say "  Other implementations: #{other_implementations.join(', ')}", :dim if other_implementations.any?

          if show_all
            say '', :clear
            say "All '#{tool_name}' implementations:", :yellow
            all_implementations = [profile.name, *other_implementations].sort
            all_implementations.each do |impl|
              impl_tool = Tool.get(impl)
              if impl_tool
                status = impl_tool.available? ? '[✓]' : '[✗]'
                color = impl_tool.available? ? :green : :red
                say "  #{status.ljust(4)} #{impl}", color
              else
                say "  [?] #{impl}", :white
              end
            rescue Ukiryu::ToolNotFoundError, Ukiryu::ProfileNotFoundError
              # Tool exists but no compatible profile for this platform
              say "  [ ] #{impl}", :dim
            end
          end
        else
          say "Tool: #{profile.name || tool_name}", :cyan
        end

        say "Display Name: #{profile.display_name || 'N/A'}", :white
        say "Version: #{profile.version || 'N/A'}", :white
        say "Homepage: #{profile.homepage || 'N/A'}", :white

        say "Aliases: #{profile.aliases.join(', ')}", :white if profile.aliases && !profile.aliases.empty?

        # Version detection
        if profile.version_detection
          vd = profile.version_detection
          say '', :clear
          say 'Version Detection:', :yellow
          command_display = vd.command.is_a?(Array) ? vd.command.join(' ') : vd.command
          say "  Command: #{command_display}", :white
          say "  Pattern: #{vd.pattern}", :white
          say "  Modern Threshold: #{vd.modern_threshold}", :white if vd.modern_threshold
        end

        # Search paths
        if profile.search_paths
          say '', :clear
          say 'Search Paths:', :yellow
          search_paths = profile.search_paths

          # Iterate over platform attributes
          %i[macos linux windows freebsd openbsd netbsd].each do |platform|
            paths = search_paths.send(platform)
            next if paths.nil? || paths.empty?

            say "  #{platform}:", :white
            Array(paths).each { |p| say "    - #{p}", :white }
          end
        end

        # Profiles
        if profile.profiles
          say '', :clear
          say "Profiles (#{profile.profiles.count}):", :yellow
          profile.profiles.each do |prof|
            platforms = Array(prof.platforms || ['all']).join(', ')
            shells = Array(prof.shells || ['all']).join(', ')
            option_style = prof.option_style || 'default'
            say "  #{prof.name || 'unnamed'}:", :white
            say "    Platforms: #{platforms}", :white
            say "    Shells: #{shells}", :white
            say "    Option Style: #{option_style}", :white
            say "    Inherits: #{prof.inherits || 'none'}", :white if prof.inherits
          end
        end

        # Availability
        say '', :clear
        if tool.available?
          say 'Status: INSTALLED', :green
          say "Executable: #{tool.executable}", :white
          say "Detected Version: #{tool.version || 'unknown'}", :white
        else
          say 'Status: NOT FOUND', :red
        end
      end

      private

      # Find other tools that implement the same interface
      #
      # @param interface_name [String] the interface name
      # @param current_tool_name [String] the current tool name to exclude
      # @return [Array<String>] list of other tool names
      def find_other_implementations(interface_name, current_tool_name)
        require_relative '../registry'

        implementations = []
        interface_sym = interface_name.to_sym

        if config.debug
          say "  [DEBUG] Looking for tools implementing '#{interface_name}' (excluding '#{current_tool_name}')", :dim
          say "  [DEBUG] Registry tools: #{Registry.tools.inspect}", :dim
        end

        Registry.tools.each do |tool_name|
          next if tool_name == current_tool_name

          begin
            # Don't pass registry_path - let it use the default
            tool_metadata = Registry.load_tool_metadata(tool_name.to_sym)
            if config.debug
              say "  [DEBUG] #{tool_name} -> metadata: #{tool_metadata ? tool_metadata.implements : 'nil'}", :dim
            end
            implementations << tool_name if tool_metadata && tool_metadata.implements == interface_sym
          rescue StandardError => e
            # Skip tools that fail to load
            say "  [DEBUG] Failed to load #{tool_name}: #{e.message}", :dim if config.debug
            next
          end
        end

        implementations.sort
      end
    end
  end
end
