# frozen_string_literal: true

module Ukiryu
  # CliCommands namespace for CLI command classes
  #
  # Each CLI command is implemented as a separate class.
  # Commands that use Thor's `subcommand` feature must be eagerly loaded.
  module CliCommands
    # Eager load base command (parent class for all commands)
    autoload :BaseCommand, 'ukiryu/cli_commands/base_command'

    # Response formatter module (used by multiple commands)
    autoload :ResponseFormatter, 'ukiryu/cli_commands/response_formatter'

    # Eager load commands used with Thor's subcommand (must be loaded at class definition time)
    autoload :ValidateCommand, 'ukiryu/cli_commands/validate_command'
    autoload :DefinitionsCommand, 'ukiryu/cli_commands/definitions_command'
    autoload :CacheCommand, 'ukiryu/cli_commands/cache_command'

    # Autoload other commands (lazy load)
    autoload :RunFileCommand, 'ukiryu/cli_commands/run_file_command'
    autoload :RunCommand, 'ukiryu/cli_commands/run_command'
    autoload :ListCommand, 'ukiryu/cli_commands/list_command'
    autoload :InfoCommand, 'ukiryu/cli_commands/info_command'
    autoload :CommandsCommand, 'ukiryu/cli_commands/commands_command'
    autoload :OptsCommand, 'ukiryu/cli_commands/opts_command'
    autoload :DescribeCommand, 'ukiryu/cli_commands/describe_command'
    autoload :WhichCommand, 'ukiryu/cli_commands/which_command'
    autoload :ConfigCommand, 'ukiryu/cli_commands/config_command'
    autoload :VersionCommand, 'ukiryu/cli_commands/version_command'
    autoload :SystemCommand, 'ukiryu/cli_commands/system_command'
    autoload :ExtractCommand, 'ukiryu/cli_commands/extract_command'
    autoload :ResolveCommand, 'ukiryu/cli_commands/resolve_command'
    autoload :RegisterCommand, 'ukiryu/cli_commands/register_command'
  end
end
