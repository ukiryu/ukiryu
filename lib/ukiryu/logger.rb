# frozen_string_literal: true

require 'logger'
require_relative 'config'

module Ukiryu
  # Ukiryu Logger with level-based message classification
  #
  # Provides structured logging with support for:
  # - Debug mode controlled by UKIRYU_DEBUG environment variable
  # - Colored output via Paint gem (when available)
  # - Message classification (debug, info, warn, error)
  # - Structured output for tool resolution process
  #
  # @example Enable debug mode
  #   ENV['UKIRYU_DEBUG'] = '1'
  #   logger = Ukiryu::Logger.new
  #   logger.debug("Tool resolution started")
  #
  # @example Standard logging
  #   logger = Ukiryu::Logger.new
  #   logger.info("Command completed successfully")
  #   logger.warn("Tool not found: #{name}")
  #   logger.error("Execution failed: #{message}")
  class Logger
    # Log levels
    LEVELS = %i[debug info warn error].freeze

    attr_reader :level, :logger, :output, :paint_available

    # Initialize a new Logger
    #
    # @param output [IO] the output stream (default: $stderr for debug, $stdout for info/warn/error)
    # @param level [Symbol] the log level (default: :warn)
    def initialize(output: nil, level: nil)
      @output = output || $stderr
      @logger = ::Logger.new(@output)
      @logger.level = ::Logger::WARN
      @paint_available = false

      # Check if debug mode is enabled via Config system
      @debug_mode = Config.debug

      # Try to load Paint for colored output
      if @debug_mode
        begin
          require 'paint'
          @paint_available = true
        rescue LoadError
          # Paint not available, fall back to plain text
        end
      end

      # Set log level based on debug mode or explicit level
      set_level(level) if level
    end

    # Set the log level
    #
    # @param level [Symbol] the log level (:debug, :info, :warn, :error)
    def set_level(level)
      level_sym = level.to_sym
      raise ArgumentError, "Invalid log level: #{level}" unless LEVELS.include?(level_sym)

      @level = level_sym
      @logger.level = case level_sym
                      when :debug then ::Logger::DEBUG
                      when :info then ::Logger::INFO
                      when :warn then ::Logger::WARN
                      when :error then ::Logger::ERROR
                      end
    end

    # Log a debug message (only when UKIRYU_DEBUG is enabled)
    #
    # @param message [String] the message
    # @param context [Hash] optional context data
    def debug(message, context = {})
      return unless @debug_mode

      @output.puts(format_message('DEBUG', message, :cyan, context))
    end

    # Log an info message
    #
    # @param message [String] the message
    # @param context [Hash] optional context data
    def info(message, context = {})
      @output.puts(format_message('INFO', message, :green, context))
    end

    # Log a warning message
    #
    # @param message [String] the message
    # @param context [Hash] optional context data
    def warn(message, context = {})
      @output.puts(format_message('WARN', message, :yellow, context))
    end

    # Log an error message
    #
    # @param message [String] the message
    # @param context [Hash] optional context data
    def error(message, context = {})
      @output.puts(format_message('ERROR', message, :red, context))
    end

    # Check if debug mode is enabled
    #
    # @return [Boolean] true if debug mode is enabled
    def debug_enabled?
      @debug_mode
    end

    # Log structured tool resolution debug information
    #
    # @param identifier [String] the tool identifier being resolved
    # @param step [Symbol] the resolution step (:header, :context, :step, :result, :not_found)
    # @param data [Hash] the step-specific data
    def debug_resolution(identifier, step, data = {})
      return unless @debug_mode

      case step
      when :header
        debug_header(identifier)
      when :context
        debug_context(data[:platform], data[:shell], data[:all_tools])
      when :step
        debug_step(data[:tool_name], data[:tool_def], data[:interface_match], data[:cached])
      when :result
        debug_result(identifier, data[:tool_name], data[:executable])
      when :not_found
        debug_not_found(identifier)
      end
    end

    # Debug section: Ukiryu CLI Options
    # Shows the options passed to the Ukiryu CLI itself (not the tool options)
    #
    # @param options [Hash] the Ukiryu CLI options
    def debug_section_ukiryu_options(options)
      return unless @debug_mode

      debug_section_header('Ukiryu CLI Options')
      options.each do |key, value|
        debug_field(key.to_s, value.inspect, boxed: false)
      end
      debug_section_footer
    end

    # Debug section: Tool Resolution
    # Shows the tool resolution process with bordered style
    #
    # @param identifier [String] the tool identifier being resolved
    # @param platform [Symbol] the detected platform
    # @param shell [Symbol] the detected shell
    # @param all_tools [Array<String>] list of all available tools
    # @param selected_tool [String] the selected tool name
    # @param executable [String] the path to the executable
    def debug_section_tool_resolution(identifier:, platform:, shell:, all_tools:, selected_tool:, executable:)
      return unless @debug_mode

      debug_section_header("Tool Resolution: #{identifier}")

      debug_field('Platform', platform.to_s, boxed: false)
      debug_field('Shell', shell.to_s, boxed: false)
      debug_field('Available Tools', all_tools.count.to_s, boxed: false)

      @output.puts ''
      @output.puts "  #{all_tools.sort.join(' • ')}"

      if @paint_available
        paint = Paint.method(:[])
        @output.puts ''
        @output.puts "#{paint['  ✓', :green]} #{paint[selected_tool, :cyan, :bright]}#{paint[' implements: ', :white]}#{paint[identifier, :yellow]}"
      else
        @output.puts ''
        @output.puts "  ✓ #{selected_tool} implements: #{identifier}"
      end
      @output.puts ''
      debug_field('Selected', selected_tool, boxed: false)
      debug_field('Executable', executable, boxed: false)

      debug_section_footer
    end

    # Debug section: Tool Not Found
    # Shows the tool not found error with bordered style
    #
    # @param identifier [String] the tool identifier being resolved
    # @param platform [Symbol] the detected platform
    # @param shell [Symbol] the detected shell
    # @param all_tools [Array<String>] list of all available tools
    def debug_section_tool_not_found(identifier:, platform:, shell:, all_tools:)
      return unless @debug_mode

      debug_section_header("Tool Resolution: #{identifier}")

      debug_field('Platform', platform.to_s, boxed: false)
      debug_field('Shell', shell.to_s, boxed: false)
      debug_field('Available Tools', all_tools.count.to_s, boxed: false)

      @output.puts ''
      @output.puts "  #{all_tools.sort.join(' • ')}"
      @output.puts ''

      if @paint_available
        paint = Paint.method(:[])
        @output.puts "#{paint['  ✗', :red]} #{paint['Tool not found', :red, :bright]}"
      else
        @output.puts '  ✗ Tool not found'
      end

      debug_section_footer
    end

    # Debug section: Structured Options (Tool Command Options)
    # Shows the structured options object that will be passed to the executable
    #
    # @param tool_name [String] the tool name
    # @param command_name [String] the command name
    # @param options_object [Object] the structured options object
    def debug_section_structured_options(tool_name, command_name, options_object)
      return unless @debug_mode

      require_relative 'models/arguments'
      debug_section_header("Structured Options (#{tool_name} #{command_name})")

      # Show the options object's attributes
      if options_object.respond_to?(:to_h)
        options_object.to_h.each do |key, value|
          debug_field(key.to_s, format_value(value), boxed: false)
        end
      elsif options_object.is_a?(Hash)
        options_object.each do |key, value|
          debug_field(key.to_s, format_value(value), boxed: false)
        end
      else
        # Try to get instance variables
        options_object.instance_variables.each do |var|
          value = options_object.instance_variable_get(var)
          debug_field(var.to_s.sub('@', ''), format_value(value), boxed: false)
        end
      end

      debug_section_footer
    end

    # Debug section: Shell Command
    # Shows the actual shell command that will be executed
    #
    # @param executable [String] the executable path
    # @param full_command [String] the full command string
    # @param env_vars [Hash] optional environment variables
    def debug_section_shell_command(executable:, full_command:, env_vars: {})
      return unless @debug_mode

      debug_section_header('Shell Command')

      debug_field('Executable', executable, boxed: false)
      debug_field('Full Command', full_command, boxed: false)

      unless env_vars.empty?
        @output.puts ''
        @output.puts '  Environment Variables:'
        env_vars.each do |key, value|
          @output.puts "    #{key}=#{value}"
        end
      end

      debug_section_footer
    end

    # Debug section: Raw Response
    # Shows the raw output from the command
    #
    # @param stdout [String] the stdout from the command
    # @param stderr [String] the stderr from the command
    # @param exit_code [Integer] the exit code
    def debug_section_raw_response(stdout:, stderr:, exit_code:)
      return unless @debug_mode

      debug_section_header('Raw Command Response')

      debug_field('Exit Code', exit_code.to_s, boxed: false)

      unless stdout.empty?
        @output.puts ''
        @output.puts '  STDOUT:'
        stdout.each_line do |line|
          @output.puts "    #{line}"
        end
      end

      unless stderr.empty?
        @output.puts ''
        @output.puts '  STDERR:'
        stderr.each_line do |line|
          @output.puts "    #{line}"
        end
      end

      debug_section_footer
    end

    # Debug section: Structured Response
    # Shows the final structured response object
    #
    # @param response [Object] the response object
    def debug_section_structured_response(response)
      return unless @debug_mode

      debug_section_header('Structured Response')

      # Show response as YAML for readability
      response_yaml = if response.respond_to?(:to_yaml)
                        response.to_yaml
                      else
                        response.inspect
                      end

      response_yaml.each_line do |line|
        @output.puts "  #{line}"
      end

      debug_section_footer
    end

    # Debug section: Execution Report (metrics)
    # Shows detailed metrics for each execution stage
    #
    # @param execution_report [ExecutionReport] the execution report
    def debug_section_execution_report(execution_report)
      return unless @debug_mode

      debug_section_header('Execution Report')

      @output.puts '  Run Environment:'
      format_env_field(@output, 'Hostname', execution_report.run_environment.hostname)
      format_env_field(@output, 'Platform', execution_report.run_environment.platform)
      format_env_field(@output, 'OS Version', execution_report.run_environment.os_version)
      format_env_field(@output, 'Shell', execution_report.run_environment.shell)
      format_env_field(@output, 'Ruby', execution_report.run_environment.ruby_version)
      format_env_field(@output, 'Ukiryu', execution_report.run_environment.ukiryu_version)
      format_env_field(@output, 'CPUs', execution_report.run_environment.cpu_count.to_s)
      format_env_field(@output, 'Memory', "#{execution_report.run_environment.total_memory}GB")

      @output.puts ''

      @output.puts '  Stage Timings:'
      execution_report.all_stages.each do |stage|
        @output.puts "    #{stage.name.ljust(20)}: #{stage.formatted_duration.ljust(10)} " \
                     "(#{stage.memory_delta}KB)" \
                     "#{stage.success ? '' : ' - FAILED'}"
        @output.puts "      #{stage.error}" unless stage.success
      end

      @output.puts ''
      @output.puts "  Total: #{execution_report.formatted_total_duration}"

      debug_section_footer
    end

    private

    # Format an environment field for debug output
    def format_env_field(output, label, value)
      output.puts "    #{label.ljust(15)}: #{value}"
    end

    # Format a value for debug display
    def format_value(value)
      case value
      when Array
        "[#{value.map(&:inspect).join(', ')}]"
      when Hash
        "{#{value.map { |k, v| "#{k.inspect}: #{v.inspect}" }.join(', ')}}"
      when String, Numeric, TrueClass, FalseClass, NilClass
        value.inspect
      else
        value.to_s
      end
    end

    # Print a debug section header (box enclosed)
    def debug_section_header(title)
      if @paint_available
        paint = Paint.method(:[])
        @output.puts ''
        @output.puts paint["┌─ #{title} #{'─' * [75 - title.length - 3, 3].max}", :cyan]
      else
        @output.puts ''
        @output.puts "┌─ #{title} #{'─' * [75 - title.length - 3, 3].max}"
      end
    end

    # Print a debug section footer
    def debug_section_footer
      if @paint_available
        paint = Paint.method(:[])
        @output.puts paint["└#{'─' * 75}", :cyan]
      else
        @output.puts "└#{'─' * 75}"
      end
    end

    # Print a debug field
    # @param label [String] the field label
    # @param value [String] the field value
    # @param boxed [Boolean] whether to draw box borders around the field
    def debug_field(label, value, boxed: true)
      if boxed
        if @paint_available
          paint = Paint.method(:[])
          @output.puts paint['║ ', :cyan] +
                       paint[label.to_s.ljust(20), :white] +
                       paint[': ', :cyan] +
                       paint[value.to_s.ljust(41), :yellow] +
                       paint['║', :cyan]
        else
          @output.puts "│ #{label.to_s.ljust(20)}: #{value.to_s.ljust(41)}│"
        end
      elsif @paint_available
        paint = Paint.method(:[])
        @output.puts paint['  ', :cyan] +
                     paint[label.to_s.ljust(20), :white] +
                     paint[': ', :cyan] +
                     paint[value.to_s, :yellow]
      else
        @output.puts "  #{label.to_s.ljust(20)}: #{value}"
      end
    end

    # Format a log message with color and context
    def format_message(level, message, color, context)
      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
      formatted = if @paint_available
                    paint = Paint.method(:[])
                    level_str = paint["[#{level}]", color]
                    time_str = timestamp # No color - let terminal decide
                    "#{time_str} #{level_str} #{message}"
                  else
                    "[#{timestamp}] [#{level}] #{message}"
                  end

      # Add context if provided
      unless context.empty?
        context_str = context.map { |k, v| "#{k}=#{v}" }.join(' ')
        formatted << " #{context_str}"
      end

      formatted
    end

    # Format debug header
    def debug_header(identifier)
      if @paint_available
        paint = Paint.method(:[])
        header = paint['🔍 Tool Resolution: ', :cyan] + paint[identifier, :yellow, :bright]
        separator = paint['─' * 60, :cyan]
      else
        header = "🔍 Tool Resolution: #{identifier}"
        separator = '─' * 60
      end
      @output.puts "\n#{header}\n#{separator}\n"
    end

    # Format debug context
    def debug_context(platform, shell, all_tools)
      if @paint_available
        paint = Paint.method(:[])
        platform_str = paint['Platform: ', :white] + paint[platform.to_s, :green]
        shell_str = paint['Shell: ', :white] + paint[shell.to_s, :green]
        tools_str = paint["Available Tools (#{all_tools.count}): ", :white] +
                    paint[all_tools.count.to_s, :yellow] + paint[' tools', :white]
        tools_list = paint['• ', :cyan] + all_tools.sort.join(paint[' • ', :cyan])
      else
        platform_str = "Platform: #{platform}"
        shell_str = "Shell: #{shell}"
        tools_str = "Available Tools (#{all_tools.count}): #{all_tools.count} tools"
        tools_list = "• #{all_tools.sort.join(' • ')}"
      end
      @output.puts "#{platform_str} | #{shell_str}\n#{tools_str}"
      @output.puts "  #{tools_list}\n"
    end

    # Format debug step
    def debug_step(tool_name, tool_def, interface_match, cached = false)
      if @paint_available
        paint = Paint.method(:[])
        status_icon = interface_match ? paint['✓', :green] : paint['◆', :yellow]
        cached_str = cached ? ' (cached)' : '' # No color - let terminal decide

        @output.puts paint["  #{status_icon} ", :white] +
                     paint[tool_name, :cyan, :bright] +
                     cached_str +
                     paint[' implements: ', :white] +
                     (tool_def.implements ? paint[tool_def.implements, :yellow] : 'none')
      else
        status_icon = interface_match ? '✓' : '◆'
        cached_str = cached ? ' (cached)' : ''
        @output.puts "  #{status_icon} #{tool_name}#{cached_str} implements: #{tool_def.implements || 'none'}"
      end
    end

    # Format debug result
    def debug_result(_identifier, tool_name, executable)
      if @paint_available
        paint = Paint.method(:[])
        separator = paint['─' * 60, :cyan]
        result_icon = paint['✅', :green]

        @output.puts "\n#{result_icon} " +
                     paint['Selected: ', :white] +
                     paint[tool_name, :cyan, :bright] +
                     paint[' | Executable: ', :white] +
                     paint[executable, :yellow]
      else
        separator = '─' * 60
        result_icon = '✅'
        @output.puts "\n#{result_icon} Selected: #{tool_name} | Executable: #{executable}"
      end
      @output.puts "#{separator}\n"
    end

    # Format debug not found
    def debug_not_found(identifier)
      if @paint_available
        paint = Paint.method(:[])
        separator = paint['─' * 60, :red]
        error_icon = paint['❌', :red]

        @output.puts "\n#{error_icon} " +
                     paint['Tool not found: ', :white] +
                     paint[identifier, :red, :bright]
      else
        separator = '─' * 60
        error_icon = '❌'
        @output.puts "\n#{error_icon} Tool not found: #{identifier}"
      end
      @output.puts "#{separator}\n"
    end
  end
end
