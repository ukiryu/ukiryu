# frozen_string_literal: true

require 'thor'
require_relative '../definition/documentation_generator'

module Ukiryu
  module CliCommands
    # Generate documentation from tool definitions
    #
    # The docs command generates human-readable documentation
    # from tool definitions in various formats.
    class DocsCommand < Thor
      class_option :verbose, type: :boolean, default: false
      class_option :format, type: :string, default: 'markdown', enum: %w[markdown md asciidoc adoc]
      class_option :output, type: :string, desc: 'Output file path'

      desc 'generate TOOL', 'Generate documentation for a tool'
      option :register, type: :string, desc: 'Register path'
      def generate(tool_name)
        generate_docs(tool_name)
      end

      desc 'generate-all', 'Generate documentation for all tools'
      option :register, type: :string, desc: 'Register path'
      option :output_dir, type: :string, desc: 'Output directory', default: 'docs'
      def generate_all
        generate_all_docs
      end

      desc 'serve', 'Serve documentation locally (experimental)'
      option :port, type: :numeric, default: 8000
      def serve
        serve_docs
      end

      private

      # Generate documentation for a tool
      #
      # @param tool_name [String] the tool name
      def generate_docs(tool_name)
        register_path = options[:register] || Ukiryu::Register.default_register_path
        tool_path = File.join(register_path, 'tools', tool_name)

        say_error("Tool not found: #{tool_name}") unless Dir.exist?(tool_path)

        # Find latest version
        version_dirs = Dir.entries(tool_path)
                          .reject { |e| e.start_with?('.') }
                          .select { |e| File.directory?(File.join(tool_path, e)) }
                          .sort { |a, b| Gem::Version.new(b) <=> Gem::Version.new(a) }

        say_error("No versions found for tool: #{tool_name}") if version_dirs.empty?

        latest_version = version_dirs.first
        definition_file = Dir.glob(File.join(tool_path, latest_version, '*.yaml')).first

        say_error("No definition file found for #{tool_name} #{latest_version}") unless definition_file

        definition = Ukiryu::Definition::Loader.load_from_file(definition_file)
        format = normalize_format

        begin
          docs = Ukiryu::Definition::DocumentationGenerator.generate(definition, format: format)
        rescue ArgumentError => e
          say_error("Error: #{e.message}")
        end

        # Output
        if options[:output]
          File.write(options[:output], docs)
          say "✓ Documentation written to: #{options[:output]}", :green
        else
          say docs, :white
        end
      end

      # Generate documentation for all tools
      def generate_all_docs
        register_path = options[:register] || Ukiryu::Register.default_register_path
        tools_dir = File.join(register_path, 'tools')

        say_error("Tools directory not found: #{tools_dir}") unless Dir.exist?(tools_dir)

        output_dir = options[:output_dir]
        FileUtils.mkdir_p(output_dir)

        count = 0
        Dir.glob(File.join(tools_dir, '*', '*/*.yaml')).each do |file|
          parts = file.split('/')
          tool_name = parts[-3]
          version = parts[-2]
          File.basename(file, '.yaml')

          definition = Ukiryu::Definition::Loader.load_from_file(file)
          format = normalize_format

          begin
            docs = Ukiryu::Definition::DocumentationGenerator.generate(definition, format: format)
          rescue ArgumentError => e
            say "Warning: Could not generate docs for #{file}: #{e.message}", :yellow
            next
          end

          # Write to file
          output_file = File.join(output_dir, "#{tool_name}-#{version}.#{format == :asciidoc ? 'adoc' : 'md'}")
          File.write(output_file, docs)
          count += 1

          say "✓ Generated: #{output_file}", :green
        end

        say '', :clear
        say "Generated #{count} documentation file(s) in: #{output_dir}", :cyan
      end

      # Serve documentation locally
      def serve_docs
        say 'Documentation server is not yet implemented.', :yellow
        say "\nFor now, you can use a simple HTTP server:", :white
        say "  python3 -m http.server #{options[:port]}", :dim
        say "  ruby -run -e httpd . -p #{options[:port]}", :dim
      end

      # Normalize format option
      #
      # @return [Symbol] normalized format
      def normalize_format
        case options[:format]
        when 'adoc'
          :asciidoc
        when 'md'
          :markdown
        else
          options[:format].to_sym
        end
      end

      # Show error message
      #
      # @param message [String] error message
      def say_error(message)
        say message, :red
        exit 1
      end
    end
  end
end
