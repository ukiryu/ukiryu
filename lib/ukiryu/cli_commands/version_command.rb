# frozen_string_literal: true

require_relative 'base_command'
require_relative '../version'

module Ukiryu
  module CliCommands
    # Show Ukiryu version
    class VersionCommand < BaseCommand
      # Execute the version command
      def run
        say "Ukiryu version #{Ukiryu::VERSION}", :cyan
      end
    end
  end
end
