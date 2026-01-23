# frozen_string_literal: true

require 'thor'
require_relative 'cli_commands/base_command'
require_relative 'cli_commands/run_file_command'
require_relative 'cli_commands/run_command'
require_relative 'cli_commands/list_command'
require_relative 'cli_commands/info_command'
require_relative 'cli_commands/commands_command'
require_relative 'cli_commands/opts_command'
require_relative 'cli_commands/describe_command'
require_relative 'cli_commands/which_command'
require_relative 'cli_commands/config_command'
require_relative 'cli_commands/version_command'
require_relative 'cli_commands/system_command'
require_relative 'cli_commands/validate_command'
require_relative 'cli_commands/extract_command'
require_relative 'thor_ext'
require_relative 'version'

module Ukiryu
  # CLI for exploring and interacting with Ukiryu tool profiles
  #
  # Each command is implemented as a separate class in the CliCommands::Commands namespace.
  # This file just delegates to those command classes, keeping each file under 200 lines.
  class Cli < Thor
    package_name 'ukiryu'

    # Extend FriendlyCLI for better Thor behavior
    extend FriendlyCLI

    # Set default registry path if not configured
    def self.exit_on_failure?
      false
    end

    desc 'run-file REQUEST_FILE', 'Execute a Ukiryu Structured Execution Request from a YAML file'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    method_option :output, aliases: :o, desc: 'Output file for response (default: stdout)', type: :string
    method_option :format, aliases: :f, desc: 'Response format (yaml, json, table, raw)', type: :string, default: 'yaml'
    method_option :dry_run, aliases: :d, desc: 'Show execution request without executing', type: :boolean,
                            default: false
    method_option :shell, desc: 'Shell to use for command execution (bash, zsh, fish, sh, powershell, cmd)', type: :string
    def run_file(request_file)
      CliCommands::RunFileCommand.new(options).run(request_file)
    end

    desc 'exec TOOL [COMMAND] [KEY=VALUE ...]', 'Execute a tool command inline'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    method_option :format, aliases: :f, desc: 'Response format (yaml, json, table, raw)', type: :string, default: 'yaml'
    method_option :output, aliases: :o, desc: 'Output file for response (default: stdout)', type: :string
    method_option :dry_run, aliases: :d, desc: 'Show execution request without executing', type: :boolean,
                            default: false
    method_option :shell, desc: 'Shell to use for command execution (bash, zsh, fish, sh, powershell, cmd)', type: :string
    method_option :stdin, desc: 'Read input from stdin (pass to command)', type: :boolean, default: false
    method_option :raw, desc: 'Output raw stdout/stderr (for pipe composition)', type: :boolean, default: false
    def exec(tool_name, command_name = nil, *params)
      CliCommands::RunCommand.new(options).run(tool_name, command_name, *params)
    end

    desc 'list', 'List all available tools in the registry'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    def list
      CliCommands::ListCommand.new(options).run
    end

    desc 'info [TOOL]', 'Show detailed information about a tool (or general info if no tool specified)'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    method_option :all, desc: 'Show all implementations for interfaces', type: :boolean, default: false
    def info(tool_name = nil)
      if tool_name.nil?
        # Show general info when no tool specified
        show_general_info
      else
        CliCommands::InfoCommand.new(options).run(tool_name)
      end
    end

    desc 'commands TOOL', 'List all commands available for a tool'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    def commands(tool_name)
      CliCommands::CommandsCommand.new(options).run(tool_name)
    end

    desc 'opts TOOL [COMMAND]', 'Show options for a tool or specific command'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    def opts(tool_name, command_name = nil)
      CliCommands::OptsCommand.new(options).run(tool_name, command_name)
    end

    desc 'describe TOOL [COMMAND]', 'Show comprehensive documentation for a tool or specific command'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    method_option :format, aliases: :f, desc: 'Output format (text, yaml, json)', type: :string, default: 'text'
    def describe(tool_name, command_name = nil)
      CliCommands::DescribeCommand.new(options).run(tool_name, command_name)
    end

    desc 'system [SUBCOMMAND]', 'Show system information (shells, etc.)'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    def system(subcommand = nil)
      CliCommands::SystemCommand.new(options).run(subcommand)
    end

    desc 'version', 'Show Ukiryu version'
    def version
      CliCommands::VersionCommand.new(options).run
    end

    desc 'which IDENTIFIER', 'Show which tool implementation would be selected'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    method_option :platform, desc: 'Platform to check (macos, linux, windows)', type: :string
    method_option :shell, desc: 'Shell to check (bash, zsh, fish, sh, powershell, cmd)', type: :string
    def which(identifier)
      CliCommands::WhichCommand.new(options).run(identifier)
    end

    desc 'config [ACTION] [KEY] [VALUE]', 'Manage configuration (list, get, set, unset)'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    def config(action = 'list', key = nil, value = nil)
      CliCommands::ConfigCommand.new(options).run(action, key, value)
    end

    desc 'validate [TOOL]', 'Validate tool profile(s) against schema'
    method_option :registry, aliases: :r, desc: 'Path to tool registry', type: :string
    def validate(tool_name = nil)
      CliCommands::ValidateCommand.new(options).run(tool_name)
    end

    desc 'extract TOOL', 'Extract tool definition from an installed CLI tool'
    method_option :output, aliases: :o, desc: 'Output file for extracted definition', type: :string
    method_option :method, aliases: :m, desc: 'Extraction method (auto, native, help)', type: :string, default: 'auto'
    method_option :verbose, aliases: :v, desc: 'Enable verbose output', type: :boolean, default: false
    def extract(tool_name)
      CliCommands::ExtractCommand.new(options).run(tool_name)
    end

    private

    # Show general information when no specific tool is requested
    def show_general_info
      require_relative 'shell'
      require_relative 'runtime'
      require_relative 'platform'

      puts "Ukiryu v#{VERSION}"
      puts ''
      puts 'System Information:'
      puts "  Platform: #{Platform.detect}"
      puts "  Shell: #{Runtime.instance.shell}"
      puts "  Ruby: #{RUBY_VERSION}"
      puts ''
      puts 'Available Shells:'
      Shell.available_shells.each do |shell|
        puts "  - #{shell}"
      end
      puts ''
      puts 'Available Commands:'
      puts '  list                    - List all available tools'
      puts '  info TOOL               - Show detailed information about a tool'
      puts '  which IDENTIFIER        - Show which tool implementation would be selected'
      puts '  commands TOOL           - List all commands available for a tool'
      puts '  opts TOOL [COMMAND]     - Show options for a tool or specific command'
      puts '  describe TOOL [COMMAND] - Show comprehensive documentation'
      puts '  config [ACTION]         - Manage configuration (list, get, set, unset)'
      puts '  system [shells]         - Show system information (shells, etc.)'
      puts '  exec ...                - Execute a tool command inline'
      puts '  run-file ...            - Execute from a YAML file'
      puts '  version                 - Show Ukiryu version'
      puts ''
      puts 'For more information on a specific command:'
      puts '  ukiryu help COMMAND'
    end
  end
end
