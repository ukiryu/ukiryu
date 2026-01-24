# frozen_string_literal: true

require_relative 'base_command'
require_relative 'response_formatter'
require_relative '../tool'
require_relative '../executor'
require_relative '../logger'
require_relative '../models/success_response'
require_relative '../models/error_response'
require_relative '../models/execution_report'
require 'yaml'

module Ukiryu
  module CliCommands
    # Execute a Ukiryu Structured Execution Request from a YAML file
    class RunFileCommand < BaseCommand
      include ResponseFormatter

      # Execute the command
      #
      # @param request_file [String] path to the request YAML file
      def run(request_file)
        setup_register

        # Output debug: Ukiryu CLI Options
        if config.debug
          logger = Ukiryu::Logger.new
          ukiryu_options = {
            format: config.format,
            debug: config.debug,
            dry_run: config.dry_run,
            output: config.output,
            register: config.register,
            request_file: request_file
          }
          logger.debug_section_ukiryu_options(ukiryu_options)
        end

        # Get format from Config (priority: CLI > ENV > programmatic > default)
        format = config.format.to_sym
        error! "Invalid format: #{format}. Must be one of: #{OUTPUT_FORMATS.join(', ')}" unless OUTPUT_FORMATS.include?(format)

        # Load execution request
        request = load_execution_request(request_file)

        if config.dry_run
          # Show dry run output
          say_dry_run(request)
          return
        end

        # Execute the request
        response = execute_request(request)

        # Output response
        output_file = config.output
        output_response(response, format, output_file, config)

        # Don't exit here - let Thor handle the result
      end

      private

      # Load execution request from YAML file
      def load_execution_request(file_path)
        error! "Request file not found: #{file_path}" unless File.exist?(file_path)

        begin
          request = YAML.safe_load(File.read(file_path), permitted_classes: [Symbol])
          validate_request!(request)
          request
        rescue Psych::SyntaxError => e
          error! "Invalid YAML in request file: #{e.message}"
        rescue StandardError => e
          error! "Error loading request file: #{e.message}"
        end
      end

      # Validate execution request structure
      def validate_request!(request)
        raise 'Request must be a YAML object (hash)' unless request.is_a?(Hash)
        raise "Request must include 'tool' field" unless request['tool']
        raise "Request must include 'command' field" unless request['command']
        raise "Request must include 'arguments' field" unless request['arguments']
        raise "'arguments' must be a YAML object (hash)" unless request['arguments'].is_a?(Hash)
      end

      # Execute the request and build response
      def execute_request(request)
        tool_name = request['tool']
        command_name = request['command']
        arguments = stringify_keys(request['arguments'])

        logger = Ukiryu::Logger.new if config.debug
        collect_metrics = config.metrics

        # Initialize execution report if metrics are enabled
        execution_report = if collect_metrics
                             Models::ExecutionReport.new(
                               tool_resolution: Models::StageMetrics.new(name: 'tool_resolution'),
                               command_building: Models::StageMetrics.new(name: 'command_building'),
                               execution: Models::StageMetrics.new(name: 'execution'),
                               response_building: Models::StageMetrics.new(name: 'response_building'),
                               run_environment: Models::RunEnvironment.collect,
                               timestamp: Time.now.iso8601
                             )
                           end

        begin
          # Stage: Tool Resolution
          execution_report.tool_resolution.start! if collect_metrics

          # Get tool - try find_by first for interface-based discovery, fallback to get
          tool = Tool.find_by(tool_name.to_sym) || Tool.get(tool_name.to_sym)
          return Models::ErrorResponse.from_message("Tool not available: #{tool_name}") unless tool

          return Models::ErrorResponse.from_message("Tool found but not executable: #{tool_name}") unless tool.available?

          execution_report.tool_resolution.finish! if collect_metrics

          # Stage: Command Building
          execution_report.command_building.start! if collect_metrics

          # Get command definition for context
          command_definition = tool.command_definition(command_name.to_sym)

          # Build options object (OOP approach)
          options_class = tool.options_for(command_name.to_sym)
          options = options_class.new
          arguments.each { |key, value| options.send("#{key}=", value) }

          execution_report.command_building.finish! if collect_metrics

          # Output debug: Structured Options (the tool's options object)
          logger.debug_section_structured_options(tool_name, command_name, options) if config.debug && logger

          # Stage: Execution
          execution_report.execution.start! if collect_metrics

          # Execute command
          result = tool.execute(command_name.to_sym, options)

          execution_report.execution.finish! if collect_metrics

          # Output debug: Shell Command
          if config.debug && logger
            logger.debug_section_shell_command(
              executable: result.command_info.executable,
              full_command: result.command_info.full_command
            )
          end

          # Output debug: Raw Response
          if config.debug && logger
            logger.debug_section_raw_response(
              stdout: result.stdout,
              stderr: result.stderr,
              exit_code: result.status
            )
          end

          # Stage: Response Building
          execution_report.response_building.start! if collect_metrics

          # Build successful response with original arguments and command definition
          response = Models::SuccessResponse.from_result(
            result,
            arguments,
            command_definition,
            execution_report: collect_metrics ? execution_report : nil
          )

          execution_report.response_building.finish! if collect_metrics

          # Calculate total duration
          execution_report.calculate_total if collect_metrics

          # Output debug: Execution Report
          logger.debug_section_execution_report(execution_report) if config.debug && logger && collect_metrics

          # Output debug: Structured Response
          logger.debug_section_structured_response(response) if config.debug && logger

          response
        rescue Ukiryu::ToolNotFoundError => e
          Models::ErrorResponse.from_message("Tool not found: #{e.message}")
        rescue Ukiryu::ProfileNotFoundError => e
          Models::ErrorResponse.from_message("Profile not found: #{e.message}")
        rescue Ukiryu::ExecutionError => e
          Models::ErrorResponse.from_message(e.message)
        rescue Ukiryu::TimeoutError => e
          Models::ErrorResponse.from_message("Command timed out: #{e.message}")
        rescue ArgumentError => e
          # Output full backtrace for debugging
          warn 'ArgumentError backtrace:' if config.debug
          e.backtrace.each { |line| warn "  #{line}" } if config.debug
          Models::ErrorResponse.from_message("Invalid arguments: #{e.message}")
        rescue StandardError => e
          # Output full backtrace for debugging
          warn 'StandardError backtrace:' if config.debug
          e.backtrace.each { |line| warn "  #{line}" } if config.debug
          Models::ErrorResponse.from_message("Unexpected error: #{e.class}: #{e.message}")
        ensure
          # Ensure metrics are finished even on error
          if collect_metrics && execution_report
            execution_report.tool_resolution.finish!(success: false) unless execution_report.tool_resolution.duration
            execution_report.command_building.finish!(success: false) unless execution_report.command_building.duration
            execution_report.execution.finish!(success: false) unless execution_report.execution.duration
            execution_report.response_building.finish!(success: false) unless execution_report.response_building.duration
          end
        end
      end
    end
  end
end
