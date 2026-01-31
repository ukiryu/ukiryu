# frozen_string_literal: true

module Ukiryu
  module CliCommands
    # Command to list system information
    class SystemCommand < BaseCommand
      # Run the system command
      #
      # @param subcommand [String, nil] the subcommand (shells, etc.)
      def run(subcommand = nil)
        case subcommand
        when 'shells', nil
          list_shells
        else
          error!("Unknown subcommand: #{subcommand}. Valid subcommands: shells")
        end
      end

      private

      # List all available shells on the system
      def list_shells
        all_shells = Ukiryu::Shell.all_valid
        platform_shells = Ukiryu::Shell.valid_for_platform
        available_shells = platform_shells.select { |shell| Ukiryu::Shell.available?(shell) }
        not_installed_shells = platform_shells.reject { |shell| Ukiryu::Shell.available?(shell) }
        not_supported_shells = all_shells - platform_shells

        say 'Available shells', :cyan
        say ''
        say '  The following shells are installed and supported on this platform:'
        say ''

        if available_shells.empty?
          say '    No supported shells detected', :dim
        else
          available_shells.each do |shell|
            say "    • #{shell_name_with_description(shell)}", :green
          end
        end

        if not_installed_shells.any?
          say ''
          say 'Additional supported shells', :cyan
          say ''
          say '  These shells are supported but not currently installed:'
          say ''

          not_installed_shells.each do |shell|
            say "    • #{shell_name_with_description(shell)}", :dim
          end
        end

        if not_supported_shells.any?
          say ''
          say 'Not available on this platform', :cyan
          say ''
          say '  These shells are not supported on this platform:'
          say ''

          not_supported_shells.each do |shell|
            say "    • #{shell_name_with_description(shell)}", :dim
          end
        end

        say ''
        say "Platform: #{Ukiryu::Platform.detect}", :dim
        say "Current shell: #{Ukiryu::Runtime.instance.shell}", :dim

        # Show shell override status
        config_shell = config.shell
        return unless config_shell

        say "Shell override: #{config_shell} (set via --shell, UKIRYU_SHELL, or config)", :yellow
      end

      # Get shell name with brief description
      #
      # @param shell_sym [Symbol] the shell symbol
      # @return [String] formatted name with description
      def shell_name_with_description(shell_sym)
        case shell_sym
        when :bash
          'bash - GNU Bourne Again SHell'
        when :zsh
          'zsh - Z shell'
        when :fish
          'fish - Friendly interactive shell'
        when :sh
          'sh - POSIX shell'
        when :powershell
          'powershell - PowerShell command-line shell'
        when :cmd
          'cmd - Windows Command Prompt'
        else
          shell_sym.to_s
        end
      end
    end
  end
end
