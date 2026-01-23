# frozen_string_literal: true

require_relative '../config'
require_relative '../shell'
require_relative '../platform'
require_relative '../runtime'

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
        require_relative '../shell'

        all_shells = Shell.all_valid
        available_shells = Shell.available_shells
        platform_shells = Shell.valid_for_platform

        say 'Available Shells on This System:', :cyan
        say ''

        if available_shells.empty?
          say '  No shells detected', :dim
        else
          available_shells.each do |shell|
            status = '✓'
            say "  #{status} #{shell}", :green
          end
        end

        say ''
        say 'All Supported Shells:', :cyan
        say ''

        all_shells.each do |shell|
          is_available = available_shells.include?(shell)
          is_platform = platform_shells.include?(shell)

          status = if is_available
                     '✓'
                   elsif is_platform
                     '✗'
                   else
                     '-'
                   end

          color = if is_available
                    :green
                  else
                    (is_platform ? :red : :dim)
                  end
          note = if !is_platform
                   ' (not supported on this platform)'
                 elsif !is_available
                   ' (supported but not found)'
                 else
                   ''
                 end

          say "  #{status} #{shell}#{note}", color
        end

        say ''
        say "Platform: #{Platform.detect}", :dim
        say "Current shell: #{Runtime.instance.shell}", :dim

        # Show shell override status
        config_shell = Config.shell
        return unless config_shell

        say "Shell override: #{config_shell} (set via --shell, UKIRYU_SHELL, or config)", :yellow
      end
    end
  end
end
