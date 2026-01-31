# frozen_string_literal: true

module Ukiryu
  module CliCommands
    # Extract tool definition from an installed CLI tool
    #
    # This command attempts to extract a tool definition by:
    # 1. Trying the tool's native --ukiryu-definition flag
    # 2. Parsing the tool's --help output as a fallback
    class ExtractCommand < BaseCommand
      # Execute the extract command
      #
      # @param tool_name [String] the tool name to extract definition from
      def run(tool_name)
        result = Ukiryu::Extractors::Extractor.extract(tool_name, extract_options)

        if result[:success]
          output_result(result)
        else
          handle_failure(result)
        end
      end

      private

      # Build extraction options from CLI options
      #
      # @return [Hash] extraction options
      def extract_options
        {
          method: options[:method]&.to_sym || :auto,
          verbose: options[:verbose]
        }
      end

      # Output the extracted definition
      #
      # @param result [Hash] extraction result
      def output_result(result)
        yaml_content = result[:yaml]

        # Write to file if output option specified
        if options[:output]
          File.write(options[:output], yaml_content)
          say "Definition extracted to: #{options[:output]}", :green
          say "Method: #{result[:method]}", :cyan if options[:verbose]
        else
          # Output to stdout
          puts yaml_content
          say "\n# Extracted using: #{result[:method]}", :cyan if options[:verbose]
        end
      end

      # Handle extraction failure
      #
      # @param result [Hash] extraction result
      def handle_failure(result)
        say "Failed to extract definition from '#{@tool_name}'", :red
        say "Error: #{result[:error]}", :red
        say '', :clear
        say 'The tool may not be installed or may not support extraction.', :yellow
        say '', :clear
        say 'Extraction methods tried:', :yellow

        if options[:method] && options[:method] != 'auto'
          say "  - #{options[:method]} (explicitly selected)", :white
        else
          say '  - native (try --ukiryu-definition flag)', :white
          say '  - help (parse --help output)', :white
        end

        say '', :clear
        say 'You can specify a method with --method:', :yellow
        say '  ukiryu extract TOOL --method native', :white
        say '  ukiryu extract TOOL --method help', :white

        exit 1
      end
    end
  end
end
