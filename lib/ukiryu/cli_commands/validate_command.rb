# frozen_string_literal: true

require_relative 'base_command'
require_relative '../registry'
require_relative '../models/validation_result'

module Ukiryu
  module CliCommands
    # Schema validation command for tool profiles
    class ValidateCommand < BaseCommand
      # Execute the validate command
      #
      # @param tool_name [String, nil] the tool name (nil to validate all)
      # @param options [Hash] command options
      def run(tool_name = nil)
        setup_registry

        if tool_name
          validate_single_tool(tool_name)
        else
          validate_all_tools
        end
      end

      private

      # Validate a single tool
      #
      # @param tool_name [String] the tool name
      def validate_single_tool(tool_name)
        result = Registry.validate_tool(tool_name, registry_path: config.registry)

        say "Validating tool: #{tool_name}", :cyan
        say '', :clear

        if result.valid?
          say result.status_message, :green
        else
          say result.status_message, :red
          say '', :clear
          result.errors.each do |error|
            say "  - #{error}", :white
          end
        end

        # Exit with error code if validation failed
        exit(result.invalid? ? 1 : 0)
      end

      # Validate all tools
      def validate_all_tools
        results = Registry.validate_all_tools(registry_path: config.registry)

        say "Validating all tools in registry: #{config.registry}", :cyan
        say '', :clear

        valid_count = 0
        invalid_count = 0
        not_found_count = 0

        results.each do |result|
          say "#{result.tool_name.ljust(20)}: #{result.status_message}", result.valid? ? :green : :red

          valid_count += 1 if result.valid?
          invalid_count += 1 if result.invalid? && !result.not_found?
          not_found_count += 1 if result.not_found?

          # Show errors for invalid tools
          if result.invalid? && !result.not_found?
            result.errors.each do |error|
              say "  - #{error}", :dim
            end
          end
        end

        say '', :clear
        say "Summary:", :cyan
        say "  Valid:   #{valid_count}", :green
        say "  Invalid: #{invalid_count}", invalid_count > 0 ? :red : :white
        say "  Missing: #{not_found_count}", not_found_count > 0 ? :yellow : :white

        # Exit with error code if any validations failed
        exit(invalid_count > 0 ? 1 : 0)
      end
    end
  end
end
