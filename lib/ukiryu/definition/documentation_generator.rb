# frozen_string_literal: true

module Ukiryu
  module Definition
    # Generate documentation from tool definitions
    #
    # This class generates human-readable documentation from tool definitions
    # in various formats (Markdown, AsciiDoc).
    class DocumentationGenerator
      # Supported formats
      FORMATS = %i[markdown asciidoc md].freeze

      class << self
        # Generate documentation for a definition
        #
        # @param definition [Hash] the definition
        # @param format [Symbol] output format (:markdown, :asciidoc)
        # @return [String] generated documentation
        def generate(definition, format: :markdown)
          format = normalize_format(format)

          case format
          when :markdown
            generate_markdown(definition)
          when :asciidoc
            generate_asciidoc(definition)
          else
            raise ArgumentError, "Unsupported format: #{format}"
          end
        end

        # Generate documentation to a file
        #
        # @param definition [Hash] the definition
        # @param file_path [String] output file path
        # @param format [Symbol] output format
        def generate_to_file(definition, file_path, format: :markdown)
          content = generate(definition, format: format)
          File.write(file_path, content)
        end

        # Generate documentation for a specific command
        #
        # @param command_name [String] the command name
        # @param command_def [Hash] the command definition
        # @param format [Symbol] output format
        # @return [String] generated command documentation
        def generate_command_docs(command_name, command_def, format: :markdown)
          format = normalize_format(format)

          case format
          when :markdown
            generate_command_markdown(command_name, command_def)
          when :asciidoc
            generate_command_asciidoc(command_name, command_def)
          else
            raise ArgumentError, "Unsupported format: #{format}"
          end
        end

        private

        # Normalize format
        #
        # @param format [Symbol] the format
        # @return [Symbol] normalized format
        def normalize_format(format)
          return :markdown if format == :md

          format
        end

        # Generate Markdown documentation
        #
        # @param definition [Hash] the definition
        # @return [String] Markdown documentation
        def generate_markdown(definition)
          output = []
          tool_name = definition[:name] || 'Unknown'
          version = definition[:version]

          # Title
          output << "# #{tool_name}"
          output << '' if version
          output << "Version: #{version}" if version
          output << ''

          # Description
          if definition[:description]
            output << definition[:description]
            output << ''
          end

          # Metadata
          output << '## Overview'
          output << ''
          output << '| Property | Value |'
          output << '|----------|-------|'
          output << "| Name | `#{tool_name}` |"
          output << "| Version | `#{version}` |" if version
          output << "| Homepage | #{definition[:homepage]} |" if definition[:homepage]
          output << ''

          # Platforms
          platforms = extract_platforms(definition)
          if platforms.any?
            output << '### Supported Platforms'
            output << ''
            platforms.each do |platform|
              shells = extract_shells_for_platform(definition, platform)
              output << "- **#{platform.to_s.capitalize}**: #{shells.join(', ')}"
            end
            output << ''
          end

          # Installation
          if definition[:install]
            output << '## Installation'
            output << ''
            output << render_installation_markdown(definition[:install])
            output << ''
          end

          # Commands
          commands = extract_commands(definition)
          if commands.any?
            output << '## Commands'
            output << ''
            commands.each do |cmd_name, cmd_def|
              output << generate_command_markdown(cmd_name, cmd_def)
            end
          end

          # Options reference
          if commands.any?
            output << '## Options Reference'
            output << ''
            commands.each do |cmd_name, cmd_def|
              options = cmd_def[:options] || []
              flags = cmd_def[:flags] || []

              next unless options.any? || flags.any?

              output << "### `#{cmd_name}`"
              output << ''

              if options.any?
                output << '#### Options'
                output << ''
                options.each do |opt|
                  output << render_option_markdown(opt)
                end
              end

              if flags.any?
                output << '#### Flags'
                output << ''
                flags.each do |flag|
                  output << render_flag_markdown(flag)
                end
              end

              output << ''
            end
          end

          output.join("\n")
        end

        # Generate command documentation in Markdown
        #
        # @param command_name [String] the command name
        # @param command_def [Hash] the command definition
        # @return [String] command documentation
        def generate_command_markdown(command_name, command_def)
          output = []
          output << "### `#{command_name}`"
          output << ''

          if command_def[:description]
            output << command_def[:description]
            output << ''
          end

          # Arguments
          if command_def[:arguments]
            output << '#### Arguments'
            output << ''
            command_def[:arguments].each do |arg|
              output << render_argument_markdown(arg)
            end
            output << ''
          end

          output.join("\n")
        end

        # Render option in Markdown
        #
        # @param opt [Hash] the option
        # @return [String] rendered option
        def render_option_markdown(opt)
          cli = opt[:cli] || opt[:name]
          required = opt[:required] ? '**(required)**' : '(optional)'
          desc = opt[:description] || ''

          output = "- `#{cli}` #{required}"
          output << " - #{desc}" if desc
          output << "\n\n  Type: `#{opt[:type]}`" if opt[:type]
          output
        end

        # Render flag in Markdown
        #
        # @param flag [Hash] the flag
        # @return [String] rendered flag
        def render_flag_markdown(flag)
          cli = flag[:cli] || flag[:name]
          desc = flag[:description] || ''

          output = "- `#{cli}`"
          output << " - #{desc}" if desc
          output
        end

        # Render argument in Markdown
        #
        # @param arg [Hash] the argument
        # @return [String] rendered argument
        def render_argument_markdown(arg)
          name = arg[:name]
          type = arg[:type] || 'any'
          desc = arg[:description] || ''
          required = arg[:required] ? '**required**' : 'optional'

          output = "- **`#{name}`** (#{type}, #{required})"
          output << " - #{desc}" if desc
          output
        end

        # Render installation instructions in Markdown
        #
        # @param install [Hash] installation instructions
        # @return [String] rendered installation
        def render_installation_markdown(install)
          output = []

          if install[:macos]
            output << '#### macOS'
            output << '```bash'
            output << install[:macos]
            output << '```'
            output << ''
          end

          if install[:linux]
            output << '#### Linux'
            output << '```bash'
            output << install[:linux]
            output << '```'
            output << ''
          end

          if install[:windows]
            output << '#### Windows'
            output << '```powershell'
            output << install[:windows]
            output << '```'
            output << ''
          end

          output.join("\n")
        end

        # Generate AsciiDoc documentation
        #
        # @param definition [Hash] the definition
        # @return [String] AsciiDoc documentation
        def generate_asciidoc(definition)
          output = []
          tool_name = definition[:name] || 'Unknown'
          version = definition[:version]

          # Title
          output << "= #{tool_name}"
          output << '' if version
          output << ':toc:' if definition[:profiles] # Only add TOC if there's content
          output << ''

          if version
            output << "Version: #{version}"
            output << ''
          end

          # Description
          if definition[:description]
            output << definition[:description]
            output << ''
          end

          # Overview
          output << '== Overview'
          output << ''
          output << '[cols="1,2"]'
          output << '|==='
          output << '| Property | Value'
          output << "| Name | `#{tool_name}`"
          output << "| Version | `#{version}`" if version
          output << "| Homepage | #{definition[:homepage]}" if definition[:homepage]
          output << '|==='
          output << ''

          # Platforms
          platforms = extract_platforms(definition)
          if platforms.any?
            output << '=== Supported Platforms'
            output << ''
            platforms.each do |platform|
              shells = extract_shells_for_platform(definition, platform)
              output << "* *#{platform.to_s.capitalize}*: #{shells.join(', ')}"
            end
            output << ''
          end

          # Commands
          commands = extract_commands(definition)
          if commands.any?
            output << '== Commands'
            output << ''
            commands.each do |cmd_name, cmd_def|
              output << generate_command_asciidoc(cmd_name, cmd_def)
            end
          end

          output.join("\n")
        end

        # Generate command documentation in AsciiDoc
        #
        # @param command_name [String] the command name
        # @param command_def [Hash] the command definition
        # @return [String] command documentation
        def generate_command_asciidoc(command_name, command_def)
          output = []
          output << "=== `#{command_name}`"
          output << ''

          if command_def[:description]
            output << command_def[:description]
            output << ''
          end

          if command_def[:arguments]
            output << '==== Arguments'
            output << ''
            command_def[:arguments].each do |arg|
              name = arg[:name]
              type = arg[:type] || 'any'
              desc = arg[:description] || ''
              required = arg[:required] ? '*required*' : 'optional'

              output << "* **`#{name}`** (#{type}, #{required})"
              output << ": #{desc}" if desc
            end
            output << ''
          end

          output.join("\n")
        end

        # Extract all platforms from definition
        #
        # @param definition [Hash] the definition
        # @return [Array<Symbol>] platforms
        def extract_platforms(definition)
          platforms = Set.new
          return platforms.to_a unless definition[:profiles]

          definition[:profiles].each do |profile|
            next unless profile[:platforms]

            profile[:platforms].each { |p| platforms.add(p) }
          end

          platforms.to_a
        end

        # Extract shells for a specific platform
        #
        # @param definition [Hash] the definition
        # @param platform [Symbol] the platform
        # @return [Array<Symbol>] shells
        def extract_shells_for_platform(definition, platform)
          shells = Set.new
          return shells.to_a unless definition[:profiles]

          definition[:profiles].each do |profile|
            next unless profile[:platforms]&.include?(platform)
            next unless profile[:shells]

            profile[:shells].each { |s| shells.add(s) }
          end

          shells.to_a.sort
        end

        # Extract all commands from definition
        #
        # @param definition [Hash] the definition
        # @return [Hash] commands
        def extract_commands(definition)
          commands = {}

          return commands unless definition[:profiles]

          definition[:profiles].each do |profile|
            next unless profile[:commands]

            profile[:commands].each do |name, cmd_def|
              commands[name] = cmd_def unless commands.key?(name)
            end
          end

          commands
        end
      end
    end
  end
end
