# frozen_string_literal: true

module Ukiryu
  module CliCommands
    # Response formatting module for CLI commands
    #
    # Provides reusable formatting methods for execution responses
    # in multiple formats (YAML, JSON, table, raw).
    module ResponseFormatter
      # Supported output formats
      OUTPUT_FORMATS = %i[yaml json table raw].freeze

      # Output response in specified format
      #
      # @param response [Models::SuccessResponse, Models::ErrorResponse] the response to format
      # @param format [Symbol] the output format (:yaml, :json, :table, or :raw)
      # @param output_file [String, nil] optional file path to write output
      # @param config [Object] the CLI config object
      # @return [void]
      def output_response(response, format, output_file, config)
        if format == :raw
          output_raw_response(response, output_file)
        else
          output_string = case format
                          when :yaml
                            format_yaml_response(response, config)
                          when :json
                            format_json_response(response)
                          when :table, :human
                            format_table_response(response, config)
                          else
                            response.to_yaml
                          end

          if output_file
            File.write(output_file, output_string)
            say "Response written to: #{output_file}", :green
          else
            say output_string
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
          say "  #{key}: #{value.inspect}", :white
        end
      end

      private

      # Format response as colored YAML
      #
      # @param response [Models::SuccessResponse, Models::ErrorResponse] the response
      # @param config [Object] the CLI config object
      # @return [String] formatted YAML
      def format_yaml_response(response, config)
        yaml_content = response.to_yaml

        # Determine if we should use colors
        # Config handles environment (NO_COLOR) and TTY detection properly
        # When config.use_color is nil, it means "auto-detect based on TTY"
        # But Docker's pseudo-TTY makes TTY detection unreliable
        # So we also check if NO_COLOR was set (via config.colors_disabled?)
        use_colors = if config.use_color.nil?
                       $stdout.tty? && !config.colors_disabled?
                     else
                       config.use_color
                     end

        return yaml_content unless use_colors

        begin
          require 'paint'
          paint = Paint.method(:[])
          # Add color coding to YAML output (no explicit newlines, let say handle it)
          yaml_content.each_line.map do |line|
            case line
            when /^status:/
              paint[line, :cyan, :bright]
            when /^exit_code:/
              paint[line, :yellow]
            when /^  executable:/
              paint[line, :green]
            when /^  full_command:/
              paint[line, :blue, :bright]
            when /^stdout:/
              line  # No color for stdout - let terminal decide
            when /^stderr:/
              paint[line, :red]
            when /^  started_at:|^  finished_at:/
              line  # No color for timestamps - let terminal decide
            when /^  duration_seconds:|^  formatted_duration:/
              paint[line, :magenta]
            else
              line
            end
          end.join
        rescue LoadError
          yaml_content
        end
      end

      # Format response as JSON
      #
      # @param response [Models::SuccessResponse, Models::ErrorResponse] the response
      # @return [String] formatted JSON
      def format_json_response(response)
        response.to_json(pretty: true)
      end

      # Output response in raw format (for pipe composition)
      #
      # In raw mode:
      # - stdout from the command is written directly to stdout
      # - stderr from the command is written directly to stderr
      # - No wrapping in YAML/JSON structures
      # - Enables clean pipe composition: echo "test" | ukiryu exec jq --raw filter="." | other_tool
      #
      # @param response [Models::SuccessResponse, Models::ErrorResponse] the response
      # @param output_file [String, nil] optional file path to write output
      # @return [void]
      def output_raw_response(response, output_file)
        if response.is_a?(Models::SuccessResponse)
          # Write stdout to stdout (without say() to avoid extra newlines)
          $stdout.write(response.output.stdout)
          $stdout.flush if response.output.stdout.empty? || response.output.stdout.end_with?("\n")

          # Write stderr to stderr
          unless response.output.stderr.empty?
            $stderr.write(response.output.stderr)
            $stderr.flush
          end

          # Write to file if specified
          File.write(output_file, response.output.stdout) if output_file
        else
          # Error response: write error message to stderr
          $stderr.write("#{response.error}\n")
          $stderr.flush
        end
      end

      # Format response as human-readable table
      #
      # @param response [Models::SuccessResponse, Models::ErrorResponse] the response
      # @param config [Object] the CLI config object
      # @return [String] formatted table
      def format_table_response(response, config)
        if response.is_a?(Models::SuccessResponse)
          format_success_table(response, config)
        else
          format_error_table(response, config)
        end
      end

      # Format success response as table
      #
      # @param response [Models::SuccessResponse] the success response
      # @param config [Object] the CLI config object
      # @return [String] formatted success table
      def format_success_table(response, config)
        return format_plain_success_table(response, config) unless defined?(Paint)

        begin
          require 'paint'
          paint = Paint.method(:[])
          success_icon = paint['✓', :green]

          output = []
          output << "#{success_icon} #{paint['Command completed successfully', :green, :bright]}\n"
          output << "#{paint['Exit code:', :white]} #{response.exit_code}\n"
          output << "#{paint['Duration:', :white]} #{response.metadata.formatted_duration}\n"
          output << "\n#{paint['Request:', :cyan, :bright]} #{format_request_summary(response.request)}\n"
          output << "\n#{paint['Command:', :cyan, :bright]} #{response.command.full_command}\n"

          unless response.output.stdout.empty?
            first_line = response.output.stdout.split("\n").first
            output << "\n#{paint['Output:', :white]} #{first_line}\n"
          end

          output << "\n#{paint['Errors:', :red]} #{response.output.stderr}\n" unless response.output.stderr.empty?

          output.join("\n")
        rescue LoadError
          format_plain_success_table(response, config)
        end
      end

      # Format request summary for table display
      #
      # @param request [Models::Request] the request object
      # @return [String] formatted request summary
      def format_request_summary(request)
        parts = []
        parts << request.options.map { |opt| "#{opt.name}=#{opt.value}" }.join(' ') unless request.options.empty?
        parts << request.flags.map { |flag| "--#{flag}" }.join(' ') unless request.flags.empty?
        parts << request.positional.map(&:value).join(' ') unless request.positional.empty?
        parts.join(' ')
      end

      # Format success response without Paint
      #
      # @param response [Models::SuccessResponse] the success response
      # @param _config [Object] the CLI config object (unused)
      # @return [String] plain text success table
      def format_plain_success_table(response, _config)
        "✓ Command completed successfully\n" \
        "Exit code: #{response.exit_code}\n" \
        "Duration: #{response.metadata.formatted_duration}\n" \
        "\nRequest: #{format_request_summary(response.request)}\n" \
        "\nCommand: #{response.command.full_command}\n"
      end

      # Format error response as table
      #
      # @param response [Models::ErrorResponse] the error response
      # @param _config [Object] the CLI config object (unused)
      # @return [String] formatted error table
      def format_error_table(response, _config)
        return "✗ Command failed: #{response.error}\n" unless defined?(Paint)

        begin
          require 'paint'
          paint = Paint.method(:[])
          error_icon = paint['✗', :red]
          "#{error_icon} #{paint['Command failed:', :red, :bright]} #{response.error}\n"
        rescue LoadError
          "✗ Command failed: #{response.error}\n"
        end
      end
    end
  end
end
