# frozen_string_literal: true

require_relative 'base_command'
require_relative '../tool'

module Ukiryu
  module CliCommands
    # Show options for a tool or specific command
    class OptsCommand < BaseCommand
      # Execute the opts command
      #
      # @param tool_name [String] the tool name
      # @param command_name [String, nil] optional command name
      def run(tool_name, command_name = nil)
        setup_registry

        # Use find_by for interface-based discovery (ping -> ping_bsd/ping_gnu)
        tool = Tool.find_by(tool_name.to_sym)
        error!("Tool not found: #{tool_name}\nAvailable tools: #{Registry.tools.sort.join(', ')}") unless tool

        tool_commands = tool.commands
        error! "No commands defined for #{tool_name}" unless tool_commands

        # Find the command
        cmds = if command_name
                 tool_commands.find { |c| c.name.to_s == command_name.to_s || c.name.to_sym == command_name.to_sym }
                 cmds ? [cmds] : []
               else
                 tool_commands
               end

        cmds.each do |cmd|
          cmd_title = command_name ? "#{tool_name} #{command_name}" : tool_name
          say '', :clear
          say "Options for #{cmd_title}:", :cyan
          say cmd.description.to_s if cmd.description

          # Arguments
          if cmd.arguments && !cmd.arguments.empty?
            say '', :clear
            say 'Arguments:', :yellow
            cmd.arguments.each do |arg|
              name = arg.name || 'unnamed'
              type = arg.type || 'unknown'
              position = arg.position || 'default'
              variadic = arg.variadic ? '(variadic)' : ''

              say "  #{name} (#{type}#{variadic})", :white
              say "    Position: #{position}", :dim if position != 'default'
              say "    Description: #{arg.description}", :dim if arg.description
            end
          end

          # Options
          if cmd.options && !cmd.options.empty?
            say '', :clear
            say 'Options:', :yellow
            cmd.options.each do |opt|
              name = opt.name || 'unnamed'
              cli = opt.cli || 'N/A'
              type = opt.type || 'unknown'
              description = opt.description || ''

              say "  --#{name.ljust(20)} #{cli}", :white
              say "    Type: #{type}", :dim
              say "    #{description}", :dim if description
              say "    Values: #{opt.values.join(', ')}", :dim if opt.values
              say "    Range: #{opt.range.join('..')}", :dim if opt.range
            end
          end

          # Post-options (options between input and output)
          if cmd.post_options && !cmd.post_options.empty?
            say '', :clear
            say 'Post-Options (between input and output):', :yellow
            cmd.post_options.each do |opt|
              name = opt.name || 'unnamed'
              cli = opt.cli || 'N/A'
              type = opt.type || 'unknown'
              description = opt.description || ''

              say "  --#{name.ljust(20)} #{cli}", :white
              say "    Type: #{type}", :dim
              say "    #{description}", :dim if description
            end
          end

          # Flags
          next unless cmd.flags && !cmd.flags.empty?

          say '', :clear
          say 'Flags:', :yellow
          cmd.flags.each do |flag|
            name = flag.name || 'unnamed'
            cli = flag.cli || 'N/A'
            default = flag.default
            default_str = default.nil? ? '' : " (default: #{default})"

            say "  #{cli.ljust(25)} #{name}#{default_str}", :white
            say "    #{flag.description}", :dim if flag.description
          end
        end
      end
    end
  end
end
