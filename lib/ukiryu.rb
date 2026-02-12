# frozen_string_literal: true

module Ukiryu
  # Core modules and classes - lazy load with autoload
  autoload :VERSION, 'ukiryu/version'
  autoload :Platform, 'ukiryu/platform'
  autoload :Shell, 'ukiryu/shell'
  autoload :Type, 'ukiryu/type'
  autoload :Executor, 'ukiryu/executor'
  autoload :Register, 'ukiryu/register'
  autoload :Tool, 'ukiryu/tool'
  autoload :OptionsBuilder, 'ukiryu/options_builder'
  autoload :SchemaValidator, 'ukiryu/schema_validator'
  autoload :IO, 'ukiryu/io'
  autoload :Config, 'ukiryu/config'
  autoload :Environment, 'ukiryu/environment'
  autoload :Logger, 'ukiryu/logger'
  autoload :Tools, 'ukiryu/tools'
  autoload :Validation, 'ukiryu/validation'
  autoload :Extractors, 'ukiryu/extractors'
  autoload :Runtime, 'ukiryu/runtime'
  autoload :ExecutionContext, 'ukiryu/execution_context'

  # Definition and models namespaces
  autoload :Definition, 'ukiryu/definition'
  autoload :Models, 'ukiryu/models'
  autoload :Errors, 'ukiryu/errors'
  autoload :Debug, 'ukiryu/debug'

  # Base classes for nested modules
  autoload :OptionsBase, 'ukiryu/options/base'
  autoload :ResponseBase, 'ukiryu/response/base'
  autoload :ActionBase, 'ukiryu/action/base'

  # CLI (optional, only load if thor is available)
  begin
    require 'thor'
    autoload :Cli, 'ukiryu/cli'
  rescue LoadError
    # Thor not available, CLI will not be available
  end

  # CliCommands namespace - autoload
  autoload :CliCommands, 'ukiryu/cli_commands'

  # Internal Tool implementation classes - lazy load with autoload
  autoload :CommandBuilder, 'ukiryu/command_builder'
  autoload :Cache, 'ukiryu/cache'
  autoload :CacheRegistry, 'ukiryu/cache_registry'
  autoload :ExecutableLocator, 'ukiryu/executable_locator'
  autoload :VersionDetector, 'ukiryu/version_detector'
  autoload :ToolIndex, 'ukiryu/tool_index'
  autoload :ManPageParser, 'ukiryu/man_page_parser'

  # Model classes - lazy load with autoload (these are directly under Ukiryu namespace)
  autoload :ToolMetadata, 'ukiryu/models/tool_metadata'
  autoload :VersionCompatibility, 'ukiryu/models/version_compatibility'

  class << self
    # Configure global Ukiryu settings
    def configure
      yield configuration
    end

    # Get global configuration
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset configuration (mainly for testing)
    def reset_configuration
      @configuration = nil
      Shell.reset
      Runtime.instance.reset!
      ExecutionContext.reset_current!
    end
  end

  # Configuration class for global settings
  class Configuration
    attr_accessor :default_shell, :register_path

    def initialize
      @default_shell = nil # Auto-detect by default
      @register_path = nil
    end
  end
end
