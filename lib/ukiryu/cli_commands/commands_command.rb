# frozen_string_literal: true

require_relative 'base_command'
require_relative '../tool'

module Ukiryu
  module CliCommands
    # List all commands available for a tool
    class CommandsCommand < BaseCommand
      # Execute the commands command
      #
      # @param tool_name [String] the tool name
      def run(tool_name)
        setup_register

        # Use find_by for interface-based discovery (ping -> ping_bsd/ping_gnu)
        tool = Tool.find_by(tool_name.to_sym)
        error!("Tool not found: #{tool_name}\nAvailable tools: #{Register.tools.sort.join(', ')}") unless tool

        tool_commands = tool.commands
        error! "No commands defined for #{tool_name}" unless tool_commands

        say "Commands for #{tool_name}:", :cyan

        # Group commands by their parent (belongs_to) for hierarchical tools
        grouped = group_commands_by_parent(tool_commands)

        if grouped.key?(nil) && grouped.size == 1
          # Flat structure - no routing/hierarchy
          grouped[nil].each do |cmd|
            display_command(cmd)
          end
        else
          # Hierarchical structure - show routing groups
          display_hierarchical_commands(tool, grouped)
        end
      end

      private

      # Group commands by their parent (belongs_to)
      #
      # @param commands [Array] list of commands
      # @return [Hash] grouped commands with nil key for top-level
      #
      def group_commands_by_parent(commands)
        grouped = Hash.new { |h, k| h[k] = [] }

        commands.each do |cmd|
          parent = cmd.belongs_to
          grouped[parent] << cmd
        end

        grouped
      end

      # Display a single command
      #
      # @param cmd [CommandDefinition] the command to display
      #
      def display_command(cmd)
        cmd_name = cmd.name || 'unnamed'
        description = cmd.description || 'No description'
        say "  #{cmd_name.to_s.ljust(20)} #{description}", :white

        # Show usage if available
        say "    Usage: #{cmd.usage}", :dim if cmd.usage

        # Show subcommand if exists
        if cmd.subcommand
          subcommand_info = cmd.subcommand.nil? ? '(none)' : cmd.subcommand
          say "    Subcommand: #{subcommand_info}", :dim
        end

        # Show cli_flag if this is a flag-based action
        return unless cmd.flag_action?

        say "    Action flag: #{cmd.cli_flag}", :dim
      end

      # Display hierarchical commands with routing information
      #
      # @param tool [Tool] the tool instance
      # @param grouped [Hash] grouped commands
      #
      def display_hierarchical_commands(tool, grouped)
        # Show routing table first
        if tool.routing?
          say '  Routing table:', :dim
          tool.routing.each_key do |key|
            target = tool.routing.resolve(key)
            say "    #{key} => #{target}", :dim
          end
          say '', :clear
        end

        # Show top-level commands (no belongs_to)
        if grouped.key?(nil) && !grouped[nil].empty?
          say '  Top-level commands:', :cyan
          grouped[nil].each do |cmd|
            display_command(cmd)
          end
          say '', :clear
        end

        # Show commands grouped by parent
        grouped.each do |parent, cmds|
          next if parent.nil?

          target = tool.routing&.resolve(parent) || parent
          say "  #{parent} commands (route to: #{target}):", :cyan
          cmds.each do |cmd|
            display_command(cmd)
          end
          say '', :clear
        end
      end
    end
  end
end
