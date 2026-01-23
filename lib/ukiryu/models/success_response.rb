# frozen_string_literal: true

require 'lutaml/model'
require_relative 'arguments'
require_relative 'command_info'
require_relative 'output_info'
require_relative 'execution_metadata'
require_relative 'execution_report'

module Ukiryu
  module Models
    # Successful CLI execution response
    #
    # Contains the complete result of a successful command execution
    # structured into three phases: Request, Command, and Output.
    # Optionally includes ExecutionReport with metrics when enabled.
    class SuccessResponse < Lutaml::Model::Serializable
      attribute :status, :string, default: 'success'
      attribute :exit_code, :integer
      attribute :request, Arguments
      attribute :command, CommandInfo
      attribute :output, OutputInfo
      attribute :metadata, ExecutionMetadata
      attribute :execution_report, ExecutionReport

      yaml do
        map_element 'status', to: :status
        map_element 'exit_code', to: :exit_code
        map_element 'request', to: :request
        map_element 'command', to: :command
        map_element 'output', to: :output
        map_element 'metadata', to: :metadata
        map_element 'execution_report', to: :execution_report
      end

      json do
        map 'status', to: :status
        map 'exit_code', to: :exit_code
        map 'request', to: :request
        map 'command', to: :command
        map 'output', to: :output
        map 'metadata', to: :metadata
        map 'execution_report', to: :execution_report
      end

      # Create a SuccessResponse from an Executor::Result
      #
      # @param result [Executor::Result] the execution result
      # @param params [Hash] the original parameters passed to the command
      # @param command_definition [CommandDefinition] the command definition for context
      # @param execution_report [ExecutionReport, nil] optional execution report with metrics
      # @return [SuccessResponse] the response model
      def self.from_result(result, params = {}, command_definition = nil, execution_report: nil)
        request = Arguments.from_params(params, command_definition)

        response = new(
          status: 'success',
          exit_code: result.status,
          request: request,
          command: CommandInfo.new(
            executable: result.executable,
            arguments: request, # Use the same structured arguments for the command
            full_command: result.command_info.full_command,
            shell: result.command_info.shell.to_s
          ),
          output: OutputInfo.new(
            stdout: result.stdout,
            stderr: result.error_output
          ),
          metadata: ExecutionMetadata.new(
            started_at: result.started_at.iso8601,
            finished_at: result.finished_at.iso8601,
            duration_seconds: result.duration,
            formatted_duration: result.metadata.formatted_duration
          )
        )

        # Add execution report if provided
        response.execution_report = execution_report if execution_report

        response
      end
    end
  end
end
