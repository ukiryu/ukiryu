# frozen_string_literal: true

module Ukiryu
  module CliCommands
    # Show Ukiryu version
    class VersionCommand < BaseCommand
      # Execute the version command
      def run
        # VERSION is defined in ukiryu/version.rb and autoloaded via main module
        say "Ukiryu version #{Ukiryu::VERSION}", :cyan
      end
    end
  end
end
