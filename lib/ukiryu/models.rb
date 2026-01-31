# frozen_string_literal: true

module Ukiryu
  module Models
    # Models namespace for tool profile model classes
    #
    # These models use lutaml-model for proper YAML serialization/deserialization

    # Autoload model classes (in separate files)
    autoload :ToolMetadata, 'ukiryu/models/tool_metadata'
    autoload :ToolDefinition, 'ukiryu/models/tool_definition'
    autoload :PlatformProfile, 'ukiryu/models/platform_profile'
    autoload :CommandDefinition, 'ukiryu/models/command_definition'
    autoload :OptionDefinition, 'ukiryu/models/option_definition'
    autoload :FlagDefinition, 'ukiryu/models/flag_definition'
    autoload :ArgumentDefinition, 'ukiryu/models/argument_definition'
    autoload :EnvVarDefinition, 'ukiryu/models/env_var_definition'
    autoload :VersionDetection, 'ukiryu/models/version_detection'
    autoload :ExecutableInfo, 'ukiryu/models/executable_info'
    autoload :ExecutionReport, 'ukiryu/models/execution_report'
    autoload :VersionCompatibility, 'ukiryu/models/version_compatibility'
    autoload :ExitCodes, 'ukiryu/models/exit_codes'
    autoload :Components, 'ukiryu/models/components'
    autoload :Routing, 'ukiryu/models/routing'
    autoload :ValidationResult, 'ukiryu/models/validation_result'
    autoload :VersionInfo, 'ukiryu/models/version_info'
    autoload :SuccessResponse, 'ukiryu/models/success_response'
    autoload :ErrorResponse, 'ukiryu/models/error_response'
    autoload :CommandInfo, 'ukiryu/models/command_info'
    autoload :Arguments, 'ukiryu/models/arguments'
    autoload :Argument, 'ukiryu/models/argument'
    autoload :ExecutionMetadata, 'ukiryu/models/execution_metadata'
    autoload :Invocation, 'ukiryu/models/invocation'
    autoload :OutputInfo, 'ukiryu/models/output_info'
  end
end
