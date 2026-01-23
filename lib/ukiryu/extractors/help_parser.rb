# frozen_string_literal: true

require_relative 'base_extractor'

module Ukiryu
  module Extractors
    # Help parser extraction strategy
    #
    # Reverse-engineers a tool definition by parsing the output
    # of the tool's `--help` command.
    class HelpParser < BaseExtractor
      # Extract definition by parsing help output
      #
      # @return [String, nil] the YAML definition or nil if extraction failed
      def extract
        return nil unless available?

        help_result = execute_command([@tool_name.to_s, '--help'])
        return nil unless help_result[:exit_status].zero?

        help_text = help_result[:stdout] + help_result[:stderr]
        return nil if help_text.strip.empty?

        # Parse help output and generate YAML
        parse_help_to_yaml(help_text)
      end

      # Check if the tool has help output
      #
      # @return [Boolean] true if --help produces output
      def available?
        help_result = execute_command([@tool_name.to_s, '--help'])
        help_result[:exit_status].zero? && !(help_result[:stdout] + help_result[:stderr]).strip.empty?
      end

      private

      # Parse help text and convert to YAML format
      #
      # @param help_text [String] the help output
      # @return [String] YAML definition
      def parse_help_to_yaml(help_text)
        require 'yaml'

        # Extract tool name from help text (usually first word)
        name = extract_name(help_text)

        # Try to detect version
        version = extract_version

        # Build basic YAML structure
        definition = {
          'ukiryu_schema' => '1.1',
          '$self' => "https://www.ukiryu.com/register/1.1/#{name}/#{version || '1.0'}",
          'name' => name,
          'version' => version || '1.0',
          'display_name' => name.capitalize,
          'profiles' => [
            {
              'name' => 'default',
              'platforms' => %w[macos linux windows],
              'shells' => %w[bash zsh fish powershell cmd],
              'commands' => []
            }
          ]
        }

        # Parse commands/options/flags from help text
        parse_help_elements(help_text, definition)

        definition.to_yaml
      end

      # Extract tool name from help text
      #
      # @param help_text [String] the help output
      # @return [String] the tool name
      def extract_name(help_text)
        # Use the tool name passed to the extractor
        @tool_name.to_s
      end

      # Try to detect tool version
      #
      # @return [String, nil] the detected version
      def extract_version
        version_result = execute_command([@tool_name.to_s, '--version'])
        if version_result[:exit_status].zero?
          version_text = version_result[:stdout]
          # Try to extract version number
          if version_text =~ /(\d+\.\d+(?:\.\d+)?)/
            return Regexp.last_match(1)
          end
        end
        nil
      end

      # Parse help elements (commands, options, flags)
      #
      # @param help_text [String] the help output
      # @param definition [Hash] the definition hash to modify
      def parse_help_elements(help_text, definition)
        # This is a basic implementation - real-world parsing would be more sophisticated
        # For now, we create a basic structure

        lines = help_text.split("\n")

        # Look for option patterns like:
        #   -v, --verbose
        #   --output=FILE
        #   -h, --help

        options = []

        lines.each do |line|
          # Match short and long options
          if line =~ /^\s*(-[a-z]),?\s*\[--([a-z-]+)(?:[=\s]+([A-Z_]+))?\]/i
            short_opt = Regexp.last_match(1)
            long_opt = Regexp.last_match(2)
            param = Regexp.last_match(3)

            option = {
              'name' => long_opt.gsub(/-/, '_'),
              'description' => line.strip
            }

            if short_opt
              option['cli'] = short_opt
            else
              option['cli'] = "--#{long_opt}"
            end

            if param
              option['type'] = infer_type(param)
            else
              option['type'] = 'boolean'
            end

            options << option
          elsif line =~ /^\s*\[--([a-z-]+)(?:[=\s]+([A-Z_]+))?\]/i
            long_opt = Regexp.last_match(1)
            param = Regexp.last_match(2)

            option = {
              'name' => long_opt.gsub(/-/, '_'),
              'cli' => "--#{long_opt}",
              'description' => line.strip
            }

            if param
              option['type'] = infer_type(param)
            else
              option['type'] = 'boolean'
            end

            options << option
          end
        end

        # Add default command with parsed options
        definition['profiles'][0]['commands'] = [
          {
            'name' => 'default',
            'description' => "Default #{@tool_name} command",
            'options' => options.uniq { |opt| opt['name'] }
          }
        ]
      end

      # Infer type from parameter name
      #
      # @param param_name [String] the parameter name
      # @return [String] the inferred type
      def infer_type(param_name)
        case param_name.upcase
        when /FILE|PATH/
          'file'
        when /NUM|COUNT|LEVEL/
          'integer'
        when /DIR|FOLDER/
          'directory'
        else
          'string'
        end
      end
    end
  end
end
