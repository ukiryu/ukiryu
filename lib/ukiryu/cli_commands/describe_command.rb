# frozen_string_literal: true

require_relative 'base_command'
require_relative '../tool'

module Ukiryu
  module CliCommands
    # Show comprehensive documentation for a tool or specific command
    class DescribeCommand < BaseCommand
      # Execute the describe command
      #
      # @param tool_name [String] the tool name
      # @param command_name [String, nil] optional command name
      def run(tool_name, command_name = nil)
        setup_register

        # Use find_by for interface-based discovery (ping -> ping_bsd/ping_gnu)
        tool = Tool.find_by(tool_name.to_sym)
        error!("Tool not found: #{tool_name}\nAvailable tools: #{Register.tools.sort.join(', ')}") unless tool

        tool_commands = tool.commands
        error! "No commands defined for #{tool_name}" unless tool_commands

        # Special handling for "help" command - show tool-level help
        if command_name&.to_s == 'help'
          show_tool_help(tool, tool_commands)
          return
        end

        # If no command specified, show overview of all commands
        unless command_name
          describe_tool_overview(tool, tool_commands)
          return
        end

        # Find the specific command
        cmd = tool_commands.find { |c| c.name.to_s == command_name.to_s || c.name.to_sym == command_name.to_sym }
        error! "Command '#{command_name}' not found for #{tool_name}\nAvailable commands: #{tool_commands.map(&:name).join(', ')}" unless cmd

        describe_command(tool, tool_name, command_name, cmd)
      end

      private

      # Show tool-level help (similar to exec help)
      def show_tool_help(tool, tool_commands)
        profile = tool.profile

        say '', :clear
        say '=' * 60, :cyan
        say "Tool: #{profile.name || tool.name}", :cyan
        say '=' * 60, :cyan
        say '', :clear

        # Basic info
        say "Display Name: #{profile.display_name || 'N/A'}", :white
        say "Version: #{profile.version || 'N/A'}", :white
        say "Homepage: #{profile.homepage || 'N/A'}", :white
        say "Aliases: #{profile.aliases.join(', ')}", :white if profile.aliases && !profile.aliases.empty?

        # Availability
        say '', :clear
        if tool.available?
          say 'Status: INSTALLED', :green
          say "Executable: #{tool.executable}", :white
          say "Detected Version: #{tool.version || 'unknown'}", :white
        else
          say 'Status: NOT FOUND', :red
        end

        # Commands
        say '', :clear
        say "Commands (#{tool_commands.count}):", :yellow
        tool_commands.each do |cmd|
          cmd_display = (cmd.name || 'unnamed').to_s.ljust(20)
          desc_display = cmd.description || 'No description'
          say "  #{cmd_display} #{desc_display}", :white

          # Show usage if available
          say "    Usage: #{cmd.usage}", :dim if cmd.usage

          # Show env var sets if available
          say "    Env Var Sets: #{cmd.use_env_vars.join(', ')}", :dim if cmd.use_env_vars && !cmd.use_env_vars.empty?
        end

        say '', :clear
        say "Usage: ukiryu exec #{tool.name} <command> [KEY=VALUE ...]", :dim
        say "   or: ukiryu exec #{tool.name} help", :dim
        say "   or: ukiryu describe #{tool.name} <command>", :dim
        say '', :clear
        say 'For more information on a specific command:', :dim
        say "  ukiryu opts #{tool.name} <command>", :dim
        say "  ukiryu describe #{tool.name} <command>", :dim
      end

      # Describe tool overview with all commands
      def describe_tool_overview(tool, tool_commands)
        profile = tool.profile

        say '', :clear
        say '=' * 60, :cyan
        say "Tool: #{profile.name || tool.name}", :cyan
        say '=' * 60, :cyan
        say '', :clear

        # Basic info
        say "Display Name: #{profile.display_name || 'N/A'}", :white
        say "Version: #{profile.version || 'N/A'}", :white
        say "Homepage: #{profile.homepage || 'N/A'}", :white
        say "Aliases: #{profile.aliases.join(', ')}", :white if profile.aliases && !profile.aliases.empty?

        # Availability
        say '', :clear
        if tool.available?
          say 'Status: INSTALLED', :green
          say "Executable: #{tool.executable}", :white
          say "Detected Version: #{tool.version || 'unknown'}", :white
        else
          say 'Status: NOT FOUND', :red
        end

        # Commands
        say '', :clear
        say "Commands (#{tool_commands.count}):", :yellow
        tool_commands.each do |cmd|
          cmd_display = (cmd.name || 'unnamed').to_s.ljust(20)
          desc_display = cmd.description || 'No description'
          say "  #{cmd_display} #{desc_display}", :white

          # Show env var sets if available
          say "    Env Var Sets: #{cmd.use_env_vars.join(', ')}", :dim if cmd.use_env_vars && !cmd.use_env_vars.empty?
        end

        say '', :clear
        say "Use 'ukiryu describe #{tool.name} <command>' for detailed command documentation", :dim
      end

      # Describe a specific command with all options, types, and option sets
      def describe_command(tool, tool_name, command_name, cmd)
        say '', :clear
        say '=' * 60, :cyan
        say "#{tool.name} #{command_name}", :cyan
        say '=' * 60, :cyan
        say '', :clear

        # Description and usage
        say cmd.description if cmd.description
        say '', :clear

        # Usage
        if cmd.usage
          say 'Usage:', :yellow
          say "  #{cmd.usage}", :white
          say '', :clear
        end

        # Subcommand
        if cmd.subcommand
          say "Subcommand: #{cmd.subcommand}", :white
          say '', :clear
        end

        # Env var sets
        if cmd.use_env_vars && !cmd.use_env_vars.empty?
          say "Env Var Sets: #{cmd.use_env_vars.join(', ')}", :white
          say '', :clear
        end

        # Arguments
        if cmd.arguments && !cmd.arguments.empty?
          say 'Arguments:', :yellow
          cmd.arguments.each do |arg|
            name = arg.name || 'unnamed'
            type = arg.type || 'string'
            required = arg.required ? 'required' : 'optional'
            variadic = arg.variadic ? '(variadic)' : ''
            position = arg.position || 'default'

            say "  #{name} (#{type}, #{required}#{variadic})", :white
            say "    Position: #{position}", :dim if position != 'default'
            say "    Description: #{arg.description}", :dim if arg.description

            # Type constraints
            if arg.min || arg.max || arg.size
              constraints = []
              constraints << "min: #{arg.min}" if arg.min
              constraints << "max: #{arg.max}" if arg.max
              constraints << "size: #{arg.size.inspect}" if arg.size
              say "    Constraints: #{constraints.join(', ')}", :dim
            end

            # Range
            say "    Range: #{arg.range.join('..')}", :dim if arg.range

            # Valid values
            say "    Valid values: #{arg.values.join(', ')}", :dim if arg.values

            say '', :clear
          end
        end

        # Options
        if cmd.options && !cmd.options.empty?
          say 'Options:', :yellow
          cmd.options.each do |opt|
            name = opt.name || 'unnamed'
            cli = opt.cli || 'N/A'
            type = opt.type || 'string'
            assignment_delimiter = opt.assignment_delimiter || 'auto'
            default = opt.default
            platforms = opt.platforms || []

            say "  #{name} (#{type})", :white
            say "    CLI: #{cli}", :dim
            say "    Assignment Delimiter: #{assignment_delimiter}", :dim if assignment_delimiter != 'auto'
            say "    Default: #{default}", :dim if default
            say "    Platforms: #{platforms.join(', ')}", :dim if platforms.any?
            say "    Description: #{opt.description}", :dim if opt.description

            # Type constraints
            say "    Range: #{opt.range.join('..')}", :dim if opt.range

            # Valid values (for symbol type)
            say "    Valid values: #{opt.values.join(', ')}", :dim if opt.values

            # Element type (for arrays)
            say "    Element type: #{opt.of}", :dim if opt.of

            say '', :clear
          end
        end

        # Post-options (options between input and output)
        if cmd.post_options && !cmd.post_options.empty?
          say 'Post-Options (between input and output):', :yellow
          cmd.post_options.each do |opt|
            name = opt.name || 'unnamed'
            cli = opt.cli || 'N/A'
            type = opt.type || 'string'

            say "  #{name} (#{type})", :white
            say "    CLI: #{cli}", :dim
            say "    Description: #{opt.description}", :dim if opt.description
            say '', :clear
          end
        end

        # Flags
        if cmd.flags && !cmd.flags.empty?
          say 'Flags:', :yellow
          cmd.flags.each do |flag|
            name = flag.name || 'unnamed'
            cli = flag.cli || 'N/A'
            default = flag.default
            platforms = flag.platforms || []

            say "  #{name} (boolean)", :white
            say "    CLI: #{cli}", :dim
            say "    Default: #{default}", :dim unless default.nil?
            say "    Platforms: #{platforms.join(', ')}", :dim if platforms.any?
            say "    Description: #{flag.description}", :dim if flag.description
            say '', :clear
          end
        end

        # Environment variables
        if cmd.env_vars && !cmd.env_vars.empty?
          say 'Environment Variables:', :yellow
          cmd.env_vars.each do |ev|
            name = ev.name || 'unnamed'
            value = ev.value
            env_var = ev.env_var
            platforms = ev.platforms || []

            say "  #{name}", :white
            say "    Value: #{value.inspect}", :dim if value
            say "    From env var: #{env_var}", :dim if env_var
            say "    Platforms: #{platforms.join(', ')}", :dim if platforms.any?
            say '', :clear
          end
        end

        # Option sets (commonly used option combinations)
        say 'Option Sets (common combinations):', :yellow
        say '  --help (show help)', :dim
        say '  --version (show version)', :dim

        # Group related options by function
        if cmd.options && !cmd.options.empty?
          output_opts = cmd.options.select { |o| o.name =~ /output|out|file|format/i }
          if output_opts.any?
            say '', :clear
            say "Output options: #{output_opts.map(&:name).join(', ')}", :dim
          end

          quality_opts = cmd.options.select { |o| o.name =~ /quality|q|compression/i }
          say "Quality options: #{quality_opts.map(&:name).join(', ')}", :dim if quality_opts.any?
        end

        # Exit codes
        # Exit codes are bound to individual commands/actions
        exit_codes = cmd.exit_codes
        if exit_codes && (exit_codes.standard_codes&.any? || exit_codes.custom_codes&.any?)
          say '', :clear
          say 'Exit Codes:', :yellow

          standard_codes = exit_codes.standard_codes
          if standard_codes&.any?
            say '  Standard:', :dim
            standard_codes.sort_by { |k, _v| k.to_i }.each do |code, meaning|
              say "    #{code.rjust(3)}: #{meaning}", :white
            end
          end

          custom_codes = exit_codes.custom_codes
          if custom_codes&.any?
            say '  Custom:', :dim
            custom_codes.sort_by { |k, _v| k.to_i }.each do |code, meaning|
              say "    #{code.rjust(3)}: #{meaning}", :white
            end
          end
        end

        say '', :clear
        say '=' * 60, :cyan
        say 'Example usage:', :yellow
        say "  ukiryu exec #{tool_name} #{command_name} key=value", :white
        say '=' * 60, :cyan
      end
    end
  end
end
