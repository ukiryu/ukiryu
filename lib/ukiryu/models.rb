# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Models namespace for tool profile model classes
    #
    # These models use lutaml-model for proper YAML serialization/deserialization

    # Autoload model classes
    autoload :Argument, 'ukiryu/models/argument'
    autoload :ArgumentDefinition, 'ukiryu/models/argument_definition'
    autoload :Arguments, 'ukiryu/models/arguments'
    autoload :CommandDefinition, 'ukiryu/models/command_definition'
    autoload :CommandInfo, 'ukiryu/models/command_info'
    autoload :Components, 'ukiryu/models/components'
    autoload :EnvVarDefinition, 'ukiryu/models/env_var_definition'
    autoload :ErrorResponse, 'ukiryu/models/error_response'
    autoload :ExecutableInfo, 'ukiryu/models/executable_info'
    autoload :ExecutionMetadata, 'ukiryu/models/execution_metadata'
    autoload :ExecutionReport, 'ukiryu/models/execution_report'
    autoload :ExecutionResult, 'ukiryu/models/execution_result'
    autoload :ExitCodes, 'ukiryu/models/exit_codes'
    autoload :FlagDefinition, 'ukiryu/models/flag_definition'
    autoload :Invocation, 'ukiryu/models/invocation'
    autoload :OptionDefinition, 'ukiryu/models/option_definition'
    autoload :OutputInfo, 'ukiryu/models/output_info'
    autoload :PlatformProfile, 'ukiryu/models/platform_profile'
    autoload :Routing, 'ukiryu/models/routing'
    autoload :RunEnvironment, 'ukiryu/models/run_environment'
    autoload :StageMetrics, 'ukiryu/models/stage_metrics'
    autoload :SuccessResponse, 'ukiryu/models/success_response'
    autoload :ToolDefinition, 'ukiryu/models/tool_definition'
    autoload :ToolMetadata, 'ukiryu/models/tool_metadata'
    autoload :ValidationResult, 'ukiryu/models/validation_result'
    autoload :VersionCompatibility, 'ukiryu/models/version_compatibility'
    autoload :VersionDetection, 'ukiryu/models/version_detection'
    autoload :VersionInfo, 'ukiryu/models/version_info'
  end
end
