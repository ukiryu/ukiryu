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
require_relative 'cli_commands/definitions_command'
require_relative 'cli_commands/cache_command'
require_relative 'cli_commands/resolve_command'
require_relative 'cli_commands/register_command'
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

    # Set default register path if not configured
    def self.exit_on_failure?
      false
    end

    desc 'run-file REQUEST_FILE', 'Execute a Ukiryu Structured Execution Request from a YAML file'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    method_option :output, aliases: :o, desc: 'Output file for response (default: stdout)', type: :string
    method_option :format, aliases: :f, desc: 'Response format (yaml, json, table, raw)', type: :string, default: 'yaml'
    method_option :dry_run, aliases: :d, desc: 'Show execution request without executing', type: :boolean,
                            default: false
    method_option :shell, desc: 'Shell to use for command execution (bash, zsh, fish, sh, powershell, cmd)',
                          type: :string
    def run_file(request_file)
      CliCommands::RunFileCommand.new(options).run(request_file)
    end

    desc 'exec TOOL [COMMAND] [KEY=VALUE ...]', 'Execute a tool command inline'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    method_option :definition, aliases: :d, desc: 'Path to tool definition file', type: :string
    method_option :format, aliases: :f, desc: 'Response format (yaml, json, table, raw)', type: :string, default: 'yaml'
    method_option :output, aliases: :o, desc: 'Output file for response (default: stdout)', type: :string
    method_option :dry_run, aliases: :D, desc: 'Show execution request without executing', type: :boolean,
                            default: false
    method_option :shell, aliases: :s,
                          desc: 'Shell to use for command execution (bash, zsh, fish, sh, powershell, cmd)', type: :string
    method_option :stdin, desc: 'Read input from stdin (pass to command)', type: :boolean, default: false
    method_option :raw, desc: 'Output raw stdout/stderr (for pipe composition)', type: :boolean, default: false
    def exec(tool_name, command_name = nil, *params)
      CliCommands::RunCommand.new(options).run(tool_name, command_name, *params)
    end

    desc 'list', 'List all available tools in the register'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    def list
      CliCommands::ListCommand.new(options).run
    end

    desc 'info [TOOL]', 'Show detailed information about a tool'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    method_option :all, desc: 'Show all implementations for interfaces', type: :boolean, default: false
    def info(tool_name = nil)
      if tool_name.nil?
        # No tool specified - show help
        help
      else
        CliCommands::InfoCommand.new(options).run(tool_name)
      end
    end

    desc 'commands TOOL', 'List all commands available for a tool'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    def commands(tool_name)
      CliCommands::CommandsCommand.new(options).run(tool_name)
    end

    desc 'opts TOOL [COMMAND]', 'Show options for a tool or specific command'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    def opts(tool_name, command_name = nil)
      CliCommands::OptsCommand.new(options).run(tool_name, command_name)
    end

    desc 'describe TOOL [COMMAND]', 'Show comprehensive documentation for a tool or specific command'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    method_option :format, aliases: :f, desc: 'Output format (text, yaml, json)', type: :string, default: 'text'
    def describe(tool_name, command_name = nil)
      CliCommands::DescribeCommand.new(options).run(tool_name, command_name)
    end

    desc 'system [SUBCOMMAND]', 'Show system information (shells, etc.)'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    def system(subcommand = nil)
      CliCommands::SystemCommand.new(options).run(subcommand)
    end

    desc 'version', 'Show Ukiryu version'
    def version
      CliCommands::VersionCommand.new(options).run
    end

    desc 'which IDENTIFIER', 'Show which tool implementation would be selected'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    method_option :platform, desc: 'Platform to check (macos, linux, windows)', type: :string
    method_option :shell, desc: 'Shell to check (bash, zsh, fish, sh, powershell, cmd)', type: :string
    def which(identifier)
      CliCommands::WhichCommand.new(options).run(identifier)
    end

    desc 'config [ACTION] [KEY] [VALUE]', 'Manage configuration (list, get, set, unset)'
    method_option :register, aliases: :r, desc: 'Path to tool register', type: :string
    def config(action = 'list', key = nil, value = nil)
      CliCommands::ConfigCommand.new(options).run(action, key, value)
    end

    desc 'validate [COMMAND]', 'Validate tool definitions'
    subcommand 'validate', CliCommands::ValidateCommand

    desc 'extract TOOL', 'Extract tool definition from an installed CLI tool'
    method_option :output, aliases: :o, desc: 'Output file for extracted definition', type: :string
    method_option :method, aliases: :m, desc: 'Extraction method (auto, native, help)', type: :string, default: 'auto'
    method_option :verbose, aliases: :v, desc: 'Enable verbose output', type: :boolean, default: false
    def extract(tool_name)
      CliCommands::ExtractCommand.new(options).run(tool_name)
    end

    desc 'definitions [COMMAND]', 'Manage tool definitions'
    subcommand 'definitions', CliCommands::DefinitionsCommand

    desc 'cache [ACTION]', 'Manage definition cache'
    subcommand 'cache', CliCommands::CacheCommand

    desc 'resolve TOOL [VERSION]', 'Resolve which definition would be used for a tool'
    def resolve(tool_name, version_constraint = nil)
      CliCommands::ResolveCommand.new(options).run(tool_name, version_constraint)
    end

    desc 'register [SUBCOMMAND]', 'Manage the tool register'
    method_option :force, aliases: :f, desc: 'Force re-clone the register', type: :boolean, default: false
    method_option :verbose, aliases: :v, desc: 'Show verbose output', type: :boolean, default: false
    def register(subcommand = nil)
      CliCommands::RegisterCommand.new(options).run(subcommand, options)
    end
  end
end
