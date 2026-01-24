# frozen_string_literal: true

require_relative '../definition'

module Ukiryu
  module CliCommands
    # CLI commands for managing tool definitions
    #
    # This command group provides functionality for:
    # - Listing discovered definitions
    # - Showing definition search paths
    # - Adding definitions to the user library
    # - Removing definitions from the user library
    # - Showing details about specific definitions
    class DefinitionsCommand < Thor
      default_command :list

      # List all discovered definitions
      #
      # @param verbose [Boolean] show detailed information
      desc 'list', 'List all discovered definitions'
      method_option :verbose, aliases: :v, desc: 'Show detailed information', type: :boolean, default: false
      def list
        definitions = Definition::Discovery.discover

        if definitions.empty?
          puts 'No definitions found.'
          puts
          puts 'Search paths:'
          Definition::Discovery.search_paths.each do |path|
            puts "  - #{path}"
          end
          return
        end

        if options[:verbose]
          # Verbose output with details
          definitions.each do |tool_name, defs|
            puts "#{tool_name}:"
            defs.each do |metadata|
              priority_indicator = defs.index(metadata).zero? ? '*' : ' '
              puts "  #{priority_indicator} #{metadata.version} (#{metadata.source_type})"
              puts "    Path: #{metadata.path}"
            end
            puts
          end
        else
          # Simple output
          definitions.each do |tool_name, defs|
            best = defs.first
            versions_str = defs.map(&:version).join(', ')
            puts "#{tool_name}: #{versions_str} [#{best.source_type}]"
          end
        end

        puts "\nLegend: * = highest priority (will be used by default)"
      end

      # Show definition search paths
      #
      desc 'path', 'Show definition search paths'
      def path
        puts 'Definition search paths (in priority order):'
        puts

        paths = Definition::Discovery.search_paths
        paths.each_with_index do |path, index|
          prefix = index.zero? ? '(1) [Highest Priority]' : "(#{index + 1})"
          exists = File.directory?(path) ? '✓' : '✗'
          puts "#{prefix} #{exists} #{path}"
        end

        puts
        puts "User directory: #{Definition::Discovery.user_definitions_directory}"
        puts "XDG_DATA_HOME: #{Definition::Discovery.xdg_data_home}"
        puts "XDG_DATA_DIRS: #{Definition::Discovery.xdg_data_dirs.join(':')}"
      end

      # Add a definition to the user library
      #
      # @param source_path [String] path to the definition file to add
      desc 'add SOURCE', 'Add definition to user library'
      method_option :name, aliases: :n, desc: 'Tool name (auto-detected from file if not specified)', type: :string
      method_option :version, aliases: :V, desc: 'Version (auto-detected from file if not specified)', type: :string
      def add(source_path)
        source_path = File.expand_path(source_path)

        unless File.exist?(source_path)
          warn "Error: Source file not found: #{source_path}"
          exit 1
        end

        # Load the definition to get metadata
        begin
          metadata = Definition::Loader.load_from_file(source_path, validation: :strict)
        rescue DefinitionLoadError, DefinitionValidationError => e
          warn "Error: Failed to load definition: #{e.message}"
          exit 1
        end

        tool_name = options[:name] || metadata.name
        version = options[:version] || metadata.version || '1.0'

        # Determine target directory
        user_dir = Definition::Discovery.user_definitions_directory
        tool_dir = File.join(user_dir, tool_name)

        # Create directories if needed
        FileUtils.mkdir_p(tool_dir)

        # Target file path
        target_path = File.join(tool_dir, "#{version}.yaml")

        # Check if target already exists
        if File.exist?(target_path)
          warn "Error: Definition already exists: #{target_path}"
          warn 'Use --name and --version to specify a different tool/version.'
          exit 1
        end

        # Copy the definition
        FileUtils.cp(source_path, target_path)

        puts 'Definition added successfully:'
        puts "  Tool: #{tool_name}"
        puts "  Version: #{version}"
        puts "  Location: #{target_path}"
      end

      # Remove a definition from the user library
      #
      # @param tool_name [String] the tool name
      desc 'remove TOOL', 'Remove definition from user library'
      method_option :version, aliases: :v, desc: 'Specific version to remove (removes all if not specified)',
                              type: :string
      method_option :force, aliases: :f, desc: 'Skip confirmation prompt', type: :boolean, default: false
      def remove(tool_name)
        user_dir = Definition::Discovery.user_definitions_directory
        tool_dir = File.join(user_dir, tool_name)

        unless File.directory?(tool_dir)
          warn "Error: No definitions found for tool '#{tool_name}'"
          warn "User definitions directory: #{user_dir}"
          exit 1
        end

        # Find versions to remove
        versions = if options[:version]
                     specific_file = File.join(tool_dir, "#{options[:version]}.yaml")
                     if File.exist?(specific_file)
                       [options[:version]]
                     else
                       warn "Error: Version #{options[:version]} not found for tool '#{tool_name}'"
                       exit 1
                     end
                   else
                     # Get all versions
                     Dir.glob(File.join(tool_dir, '*.yaml')).map do |file|
                       File.basename(file, '.yaml')
                     end
                   end

        # Confirm removal
        unless options[:force]
          puts 'This will remove the following definitions:'
          versions.each do |v|
            puts "  - #{tool_name}/#{v}"
          end
          print 'Are you sure? [y/N] '
          response = $stdin.gets.chomp
          unless response.downcase == 'y'
            puts 'Cancelled.'
            return
          end
        end

        # Remove files
        versions.each do |v|
          file_path = File.join(tool_dir, "#{v}.yaml")
          FileUtils.rm(file_path)
          puts "Removed: #{tool_name}/#{v}"
        end

        # Remove tool directory if empty
        if Dir.empty?(tool_dir)
          FileUtils.rmdir(tool_dir)
          puts "Removed empty directory: #{tool_dir}"
        end

        puts 'Done.'
      end

      # Show details about a specific definition
      #
      # @param tool_name [String] the tool name
      desc 'info TOOL', 'Show definition details'
      method_option :version, aliases: :v, desc: 'Specific version to show (shows best available if not specified)',
                              type: :string
      def info(tool_name)
        definitions = Definition::Discovery.definitions_for(tool_name)

        if definitions.nil? || definitions.empty?
          warn "Error: No definitions found for tool '#{tool_name}'"
          exit 1
        end

        # Find the requested version or best available
        metadata = if options[:version]
                     definitions.find { |d| d.version == options[:version] }
                   else
                     definitions.first
                   end

        unless metadata
          warn "Error: Version '#{options[:version]}' not found for tool '#{tool_name}'"
          warn "Available versions: #{definitions.map(&:version).join(', ')}"
          exit 1
        end

        # Show details
        puts "Tool: #{metadata.name}"
        puts "Version: #{metadata.version}"
        puts "Source: #{metadata.source_type}"
        puts "Path: #{metadata.path}"
        puts "Exists: #{metadata.exists? ? 'Yes' : 'No'}"
        puts "Modified: #{metadata.mtime}" if metadata.exists?

        # Show all available versions
        if definitions.length > 1
          puts
          puts 'Available versions:'
          definitions.each do |defn|
            current = defn.version == metadata.version
            indicator = current ? '*' : ' '
            priority_note = defn == definitions.first ? ' [default]' : ''
            puts "  #{indicator} #{defn.version} (#{defn.source_type})#{priority_note}"
          end
        end

        # Try to load and validate the definition
        puts
        begin
          tool_def = metadata.load_definition
          puts 'Validation: ✓ Valid'
          puts "Display Name: #{tool_def.display_name}" if tool_def.display_name
          puts "Homepage: #{tool_def.homepage}" if tool_def.homepage
        rescue DefinitionLoadError, DefinitionValidationError => e
          puts 'Validation: ✗ Invalid'
          puts "Error: #{e.message}"
        end
      end
    end
  end
end
