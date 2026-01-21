# frozen_string_literal: true

require "thor"
require "ukiryu"
require_relative "version"

module Ukiryu
  # CLI for exploring and interacting with Ukiryu tool profiles
  class Cli < Thor
    package_name "ukiryu"

    # Set default registry path if not configured
    def self.exit_on_failure?
      false
    end

    desc "list", "List all available tools in the registry"
    method_option :registry, aliases: :r, desc: "Path to tool registry", type: :string
    def list
      setup_registry(options[:registry])

      tools = Registry.tools
      if tools.empty?
        say "No tools found in registry", :red
        return
      end

      say "Available tools (#{tools.count}):", :cyan
      tools.sort.each do |name|
        begin
          tool = Tool.get(name)
          version_info = tool.version ? "v#{tool.version}" : "version unknown"
          available = tool.available? ? "[✓]" : "[✗]"
          say "  #{available.ljust(4)} #{name.ljust(20)} #{version_info}", tool.available? ? :green : :red
        rescue Ukiryu::Error => e
          say "  [?] #{name.ljust(20)} error: #{e.message}", :red
        end
      end
    end

    desc "info TOOL", "Show detailed information about a tool"
    method_option :registry, aliases: :r, desc: "Path to tool registry", type: :string
    def info(tool_name)
      setup_registry(options[:registry])

      tool = Tool.get(tool_name)
      profile = tool.profile

      say "", :clear
      say "Tool: #{profile[:name] || tool_name}", :cyan
      say "Display Name: #{profile[:display_name] || 'N/A'}", :white
      say "Version: #{profile[:version] || 'N/A'}", :white
      say "Homepage: #{profile[:homepage] || 'N/A'}", :white

      if profile[:aliases] && !profile[:aliases].empty?
        say "Aliases: #{profile[:aliases].join(', ')}", :white
      end

      # Version detection
      if profile[:version_detection]
        vd = profile[:version_detection]
        say "", :clear
        say "Version Detection:", :yellow
        say "  Command: #{vd[:command]}", :white
        say "  Pattern: #{vd[:pattern]}", :white
        if vd[:modern_threshold]
          say "  Modern Threshold: #{vd[:modern_threshold]}", :white
        end
      end

      # Search paths
      if profile[:search_paths]
        say "", :clear
        say "Search Paths:", :yellow
        profile[:search_paths].each do |platform, paths|
          next if paths.nil? || paths.empty?
          say "  #{platform}:", :white
          Array(paths).each { |p| say "    - #{p}", :white }
        end
      end

      # Profiles
      if profile[:profiles]
        say "", :clear
        say "Profiles (#{profile[:profiles].count}):", :yellow
        profile[:profiles].each do |prof|
          platforms = Array(prof[:platforms] || ['all']).join(', ')
          shells = Array(prof[:shells] || ['all']).join(', ')
          say "  #{prof[:name] || 'unnamed'}:", :white
          say "    Platforms: #{platforms}", :white
          say "    Shells: #{shells}", :white
          say "    Version: #{prof[:version] || 'any'}", :white
        end
      end

      # Availability
      say "", :clear
      if tool.available?
        say "Status: INSTALLED", :green
        say "Executable: #{tool.executable}", :white
        say "Detected Version: #{tool.version || 'unknown'}", :white
      else
        say "Status: NOT FOUND", :red
      end
    end

    desc "commands TOOL", "List all commands available for a tool"
    method_option :registry, aliases: :r, desc: "Path to tool registry", type: :string
    def commands(tool_name)
      setup_registry(options[:registry])

      tool = Tool.get(tool_name)
      commands = tool.commands

      unless commands
        say "No commands defined for #{tool_name}", :red
        return
      end

      say "Commands for #{tool_name}:", :cyan
      commands.each do |cmd_name, cmd|
        cmd_name = cmd_name || 'unnamed'
        description = cmd[:description] || 'No description'
        say "  #{cmd_name.to_s.ljust(20)} #{description}", :white

        # Show usage if available
        if cmd[:usage]
          say "    Usage: #{cmd[:usage]}", :dim
        end

        # Show subcommand if exists
        if cmd[:subcommand]
          subcommand_info = cmd[:subcommand].nil? ? '(none)' : cmd[:subcommand]
          say "    Subcommand: #{subcommand_info}", :dim
        end
      end
    end

    desc "opts TOOL [COMMAND]", "Show options for a tool or specific command"
    method_option :registry, aliases: :r, desc: "Path to tool registry", type: :string
    def opts(tool_name, command_name = nil)
      setup_registry(options[:registry])

      tool = Tool.get(tool_name)
      commands = tool.commands

      unless commands
        say "No commands defined for #{tool_name}", :red
        return
      end

      # Find the command
      cmds = if command_name
                cmd = commands[command_name.to_sym] || commands[command_name]
                cmd ? [cmd] : []
              else
                commands.values
              end

      cmds.each do |cmd|
        cmd_title = command_name ? "#{tool_name} #{command_name}" : tool_name
        say "", :clear
        say "Options for #{cmd_title}:", :cyan
        say "#{cmd[:description]}" if cmd[:description]

        # Arguments
        if cmd[:arguments] && !cmd[:arguments].empty?
          say "", :clear
          say "Arguments:", :yellow
          cmd[:arguments].each do |arg|
            name = arg[:name] || 'unnamed'
            type = arg[:type] || 'unknown'
            position = arg[:position] || 'default'
            variadic = arg[:variadic] ? '(variadic)' : ''

            say "  #{name} (#{type}#{variadic})", :white
            say "    Position: #{position}", :dim if position != 'default'
            say "    Description: #{arg[:description]}", :dim if arg[:description]
          end
        end

        # Options
        if cmd[:options] && !cmd[:options].empty?
          say "", :clear
          say "Options:", :yellow
          cmd[:options].each do |opt|
            name = opt[:name] || 'unnamed'
            cli = opt[:cli] || 'N/A'
            type = opt[:type] || 'unknown'
            description = opt[:description] || ''

            say "  --#{name.ljust(20)} #{cli}", :white
            say "    Type: #{type}", :dim
            say "    #{description}", :dim if description
            if opt[:values]
              say "    Values: #{opt[:values].join(', ')}", :dim
            end
            if opt[:range]
              say "    Range: #{opt[:range].join('..')}", :dim
            end
          end
        end

        # Post-options (options between input and output)
        if cmd[:post_options] && !cmd[:post_options].empty?
          say "", :clear
          say "Post-Options (between input and output):", :yellow
          cmd[:post_options].each do |opt|
            name = opt[:name] || 'unnamed'
            cli = opt[:cli] || 'N/A'
            type = opt[:type] || 'unknown'
            description = opt[:description] || ''

            say "  --#{name.ljust(20)} #{cli}", :white
            say "    Type: #{type}", :dim
            say "    #{description}", :dim if description
          end
        end

        # Flags
        if cmd[:flags] && !cmd[:flags].empty?
          say "", :clear
          say "Flags:", :yellow
          cmd[:flags].each do |flag|
            name = flag[:name] || 'unnamed'
            cli = flag[:cli] || 'N/A'
            default = flag[:default]
            default_str = default.nil? ? '' : " (default: #{default})"

            say "  #{cli.ljust(25)} #{name}#{default_str}", :white
            say "    #{flag[:description]}", :dim if flag[:description]
          end
        end
      end
    end

    desc "execute TOOL COMMAND [OPTIONS]", "Execute a tool command with options"
    method_option :registry, aliases: :r, desc: "Path to tool registry", type: :string
    method_option :inputs, aliases: :i, desc: "Input files", type: :array
    method_option :output, aliases: :o, desc: "Output file", type: :string
    method_option :dry_run, aliases: :d, desc: "Show command without executing", type: :boolean, default: false
    def execute(tool_name, command_name, **extra_opts)
      setup_registry(options[:registry])

      tool = Tool.get(tool_name)

      # Build params from options
      params = {}
      params[:inputs] = options[:inputs] if options[:inputs]
      params[:output] = options[:output] if options[:output]

      # Add extra options as params
      extra_opts.each do |key, value|
        params[key.to_sym] = value
      end

      if options[:dry_run]
        # Show what would be executed without actually running
        say "DRY RUN - Would execute:", :yellow
        say "  Tool: #{tool_name}", :white
        say "  Command: #{command_name}", :white
        say "  Parameters:", :white
        params.each do |k, v|
          say "    #{k}: #{v.inspect}", :dim
        end
      else
        result = tool.execute(command_name.to_sym, params)

        if result.success?
          say "Command completed successfully", :green
          say "Exit status: #{result.status}", :white
          say "Duration: #{result.metadata.formatted_duration}", :white

          if result.output.stdout && !result.output.stdout.empty?
            say "", :clear
            say "STDOUT:", :yellow
            say result.output.stdout
          end

          if result.output.stderr && !result.output.stderr.empty?
            say "", :clear
            say "STDERR:", :yellow
            say result.output.stderr
          end
        else
          say "Command failed", :red
          say "Exit status: #{result.status}", :white
          say "Duration: #{result.metadata.formatted_duration}", :white

          if result.output.stdout && !result.output.stdout.empty?
            say "", :clear
            say "STDOUT:", :yellow
            say result.output.stdout
          end

          if result.output.stderr && !result.output.stderr.empty?
            say "", :clear
            say "STDERR:", :yellow
            say result.output.stderr
          end

          exit 1
        end
      end
    end

    desc "version", "Show Ukiryu version"
    def version
      say "Ukiryu version #{Ukiryu::VERSION}", :cyan
    end

    private

    def setup_registry(custom_path)
      registry_path = custom_path ||
                       ENV['UKIRYU_REGISTRY'] ||
                       default_registry_path
      if registry_path && Dir.exist?(registry_path)
        Registry.default_registry_path = registry_path
      end
    end

    def default_registry_path
      # Try multiple approaches to find the registry
      # 1. Check environment variable
      env_path = ENV['UKIRYU_REGISTRY']
      return env_path if env_path && Dir.exist?(env_path)

      # 2. Try relative to gem location
      # From lib/ukiryu/cli.rb, go up to gem root, then to sibling register/
      gem_root = File.dirname(File.dirname(File.dirname(__FILE__)))
      registry_path = File.join(gem_root, '..', 'register')
      if Dir.exist?(registry_path)
        return File.expand_path(registry_path)
      end

      # 3. Try from current directory (development setup)
      current = File.expand_path('../register', Dir.pwd)
      return current if Dir.exist?(current)

      # 4. Try from parent directory
      parent = File.expand_path('../../register', Dir.pwd)
      return parent if Dir.exist?(parent)

      nil
    end
  end
end
