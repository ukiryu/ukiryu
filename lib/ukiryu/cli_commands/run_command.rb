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
    # Execute a tool command inline (shorthand for run)
    class RunCommand < BaseCommand
      include ResponseFormatter

      # Execute the command
      #
      # @param tool_name [String] the tool name
      # @param command_name [String, nil] the command name (optional, uses default if nil)
      # @param params [Array<String>] key=value parameter pairs
      def run(tool_name, command_name = nil, *params)
        setup_register

        # Handle the case where command_name is omitted and first param is a key=value pair
        # When user types: ukiryu exec-inline ping host=127.0.0.1
        # Thor interprets it as: tool_name="ping", command_name="host=127.0.0.1", params=["count=1"]
        # We need to detect if command_name looks like a parameter
        if command_name&.include?('=')
          # command_name is actually a parameter, shift it back to params
          params.unshift(command_name)
          command_name = nil
        end

        # Special handling for "help" command
        if command_name&.to_s == 'help'
          show_tool_help(tool_name, params)
          return
        end

        # Resolve command name if not provided
        command_name ||= resolve_default_command(tool_name)

        # Parse key=value pairs into arguments hash
        arguments = parse_inline_params(params)

        # Handle stdin from CLI flag (--stdin) or special parameter (stdin=-)
        if options[:stdin] || arguments[:stdin] == '-'
          # Read from actual stdin
          stdin_data = $stdin.read
          arguments[:stdin] = stdin_data
        elsif arguments[:stdin]
          # stdin parameter contains data (string or file path)
          # If it starts with @, treat as file path
          if arguments[:stdin].is_a?(String) && arguments[:stdin].start_with?('@')
            file_path = arguments[:stdin][1..]
            begin
              arguments[:stdin] = File.read(file_path)
            rescue Errno::ENOENT
              error! "File not found: #{file_path}"
            end
          end
          # Otherwise, use the value as-is (already a string or IO object)
        end

        # Build execution request
        request = {
          'tool' => tool_name,
          'command' => command_name,
          'arguments' => arguments
        }

        # Output debug: Ukiryu CLI Options
        if config.debug
          logger = Ukiryu::Logger.new
          ukiryu_options = {
            format: config.format,
            debug: config.debug,
            dry_run: config.dry_run,
            output: config.output,
            register: config.register,
            stdin: !arguments[:stdin].nil?
          }
          logger.debug_section_ukiryu_options(ukiryu_options)
        end

        # Get format from Config (priority: CLI > ENV > programmatic > default)
        # --raw flag overrides the format setting
        format = if options[:raw]
                   :raw
                 else
                   config.format.to_sym
                 end
        error! "Invalid format: #{format}. Must be one of: #{OUTPUT_FORMATS.join(', ')}" unless OUTPUT_FORMATS.include?(format)

        if config.dry_run
          # Show dry run output
          say_dry_run(request)
          return
        end

        # Execute the request
        response = execute_request(request, tool_name, command_name)

        # Output response
        output_file = config.output
        output_response(response, format, output_file, config)

        # Don't exit here - let Thor handle the result
      end

      private

      # Resolve the default command for a tool
      # Uses the tool's default_command from profile, or falls back to the interface it implements
      #
      # @param tool_name [String] the tool name
      # @return [String] the resolved command name
      def resolve_default_command(tool_name)
        # If --definition is provided, load from definition file
        if options[:definition]
          tool = Tool.load(options[:definition], validation: :strict)
          metadata = tool.profile
        else
          # Use Register to load tool metadata without full resolution
          # This avoids triggering debug output for "Tool Resolution" twice
          require_relative '../register'
          require_relative '../models/tool_metadata'

          metadata = Register.load_tool_metadata(tool_name.to_sym, register_path: config.register)
          error! "Tool not found: #{tool_name}" unless metadata
        end

        # Get the default command (checks YAML default_command, then implements, then tool name)
        command = metadata.default_command
        return command.to_s if command

        # Fallback
        'default'
      end

      # Parse inline key=value params into a hash
      def parse_inline_params(params_array)
        arguments = {}

        params_array.each do |param|
          if param.include?('=')
            key, value = param.split('=', 2)

            # Special case: stdin parameter with special values should be treated as string literals
            # - stdin=- : marker for reading from actual stdin
            # - stdin=@filename : marker for reading from file
            # These syntaxes use characters that are invalid YAML, so skip YAML parsing
            skip_yaml_parse = key == 'stdin' && (value == '-' || value.start_with?('@'))

            unless skip_yaml_parse
              # Try to parse value as YAML to handle types properly
              begin
                parsed_value = YAML.safe_load(value, permitted_classes: [Symbol])
                value = parsed_value
              rescue StandardError
                # Keep as string if YAML parsing fails
              end

              # Convert key to symbol for consistency with API
            end
            arguments[key.to_sym] = value
          else
            error! "Invalid parameter format: #{param}. Use key=value"
          end
        end

        arguments
      end

      # Execute the request and build response
      def execute_request(request, tool_name = nil, command_name = nil)
        tool_name ||= request['tool']
        command_name ||= request['command']
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

          # Load tool from definition file if --definition option provided
          if options[:definition]
            tool = Tool.load(options[:definition], validation: :strict)
            # Verify that the tool name matches (if user specified one)
            if tool_name && tool.name.to_sym != tool_name.to_sym
              return Models::ErrorResponse.from_message(
                "Tool name mismatch: definition file contains '#{tool.name}' but command specified '#{tool_name}'"
              )
            end
          else
            # Get tool - try find_by first for interface-based discovery, fallback to get
            tool = Tool.find_by(tool_name.to_sym) || Tool.get(tool_name.to_sym)
          end

          return Models::ErrorResponse.from_message("Tool not available: #{tool_name}") unless tool

          return Models::ErrorResponse.from_message("Tool found but not executable: #{tool_name}") unless tool.available?

          execution_report.tool_resolution.finish! if collect_metrics

          # Stage: Command Building
          execution_report.command_building.start! if collect_metrics

          # Get command definition for context
          command_definition = tool.command_definition(command_name.to_sym)

          # Build options object (OOP approach)
          # Note: stdin is a special parameter, not passed to options
          options_arguments = arguments.reject { |k, _| k == :stdin }
          options_class = tool.options_for(command_name.to_sym)
          options = options_class.new
          options_arguments.each { |key, value| options.send("#{key}=", value) }

          execution_report.command_building.finish! if collect_metrics

          # Output debug: Structured Options (the tool's options object)
          logger.debug_section_structured_options(tool_name, command_name, options) if config.debug && logger

          # Stage: Execution
          execution_report.execution.start! if collect_metrics

          # Execute command (pass arguments hash with stdin, not just options object)
          result = tool.execute(command_name.to_sym, arguments)

          execution_report.execution.finish! if collect_metrics

          # Output debug: Shell Command
          if config.debug && logger
            # CommandInfo doesn't have env_vars, so we pass empty hash
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

      # Show dry run output
      #
      # @param request [Hash] the execution request
      def say_dry_run(request)
        say 'DRY RUN - Ukiryu Structured Execution Request:', :yellow
        say '', :clear
        say "Tool: #{request['tool']}", :cyan
        say "Command: #{request['command']}", :cyan
        say 'Arguments:', :cyan
        request['arguments'].each do |key, value|
          if key == :stdin
            # Show stdin preview (first 100 chars)
            preview = value.is_a?(String) ? value[0..100] : '[IO Stream]'
            preview += '...' if value.is_a?(String) && value.length > 100
            say "  #{key}: #{preview.inspect}", :white
          else
            say "  #{key}: #{value.inspect}", :white
          end
        end
      end

      # Show help information for a tool
      #
      # @param tool_name [String] the tool name
      # @param params [Array<String>] additional parameters
      def show_tool_help(tool_name, _params = [])
        setup_register

        # Load tool from definition file if --definition option provided
        tool = if options[:definition]
                 Tool.load(options[:definition], validation: :strict)
               else
                 # Use find_by for interface-based discovery
                 Tool.find_by(tool_name.to_sym)
               end

        error! "Tool not found: #{tool_name}\nAvailable tools: #{Register.tools.sort.join(', ')}" unless tool

        say '', :clear
        say "Tool: #{tool.name}", :cyan
        say "Display Name: #{tool.profile.display_name || 'N/A'}", :white
        say "Version: #{tool.profile.version || 'N/A'}", :white
        say "Homepage: #{tool.profile.homepage || 'N/A'}", :white
        say '', :clear

        # Show available commands
        tool_commands = tool.commands
        if tool_commands && !tool_commands.empty?
          say 'Available commands:', :cyan

          tool_commands.each do |cmd|
            cmd_name = cmd.name || 'unnamed'
            description = cmd.description || ''
            say "  #{cmd_name.to_s.ljust(20)} #{description}", :white

            # Show usage if available
            say "    Usage: #{cmd.usage}", :dim if cmd.usage

            # Show subcommand if exists
            if cmd.subcommand
              subcommand_info = cmd.subcommand.nil? ? '(none)' : cmd.subcommand
              say "    Subcommand: #{subcommand_info}", :dim
            end
          end

          say '', :clear
          say "Usage: ukiryu exec #{tool.name} <command> [KEY=VALUE ...]", :dim
          say "   or: ukiryu exec #{tool.name} help", :dim
          say "   or: ukiryu describe #{tool.name} <command>", :dim
          say '', :clear
          say 'For more information on a specific command:', :dim
          say "  ukiryu opts #{tool.name} <command>", :dim
          say "  ukiryu describe #{tool.name} <command>", :dim
        else
          say 'This tool has no defined commands (it may be a simple wrapper)', :dim
          say "Usage: ukiryu exec #{tool.name} [KEY=VALUE ...]", :dim
        end
      end
    end
  end
end
