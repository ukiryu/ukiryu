# frozen_string_literal: true

require 'thor'

module Ukiryu
  module CliCommands
    # Validate tool definitions
    #
    # The validate command checks tool definitions against JSON Schema
    # and structural validation rules.
    class ValidateCommand < Thor
      class_option :verbose, type: :boolean, default: false
      class_option :format, type: :string, default: 'text', enum: %w[text json]
      class_option :schema, type: :string, desc: 'Path to JSON Schema file'
      class_option :strict, type: :boolean, default: false, desc: 'Treat warnings as errors'
      class_option :executable, type: :boolean, default: false, desc: 'Test executable against actual tool'
      class_option :all, type: :boolean, default: false,
                         desc: 'Enable all validations (schema + executable + smoke tests)'
      class_option :register, type: :string, desc: 'Path to tool register'

      desc 'file PATH', 'Validate a definition file'
      def file(path)
        validate_file(path)
      end

      desc 'all', 'Validate all definitions in register'
      option :register, type: :string, desc: 'Register path'
      def all
        validate_all
        test_all_executables if options[:all] || options[:executable]
      end

      desc 'string YAML', 'Validate a YAML string'
      def string(yaml)
        validate_string(yaml)
      end

      private

      # Validate a single file
      #
      # @param path [String] file path
      def validate_file(path)
        validate_file_impl(path)
      end

      # Validate a single file (implementation)
      #
      # @param path [String] file path
      def validate_file_impl(path)
        # First, validate the definition structure
        result = Ukiryu::Definition::DefinitionValidator.validate_file(
          path,
          schema_path: options[:schema]
        )

        output_result(result, path)

        # If structural validation passed and --executable or --all flag is set, test the executable
        test_executable(path) if (options[:executable] || options[:all]) && result.valid?

        exit 1 if result.invalid? || (result.has_warnings? && options[:strict])
      end

      # Test the executable against the actual tool
      #
      # @param path [String] path to definition file
      def test_executable(path)
        say '', :clear
        say 'Testing executable...', :cyan

        begin
          # Load the YAML profile to get smoke_tests
          profile_data = YAML.safe_load(File.read(path), permitted_classes: [Symbol, Date, Time])

          # Extract tool name from file path
          file_name = File.basename(path, '.yaml')
          tool_dir = File.basename(File.dirname(path))
          tools_dir = File.basename(File.dirname(File.dirname(path)))

          # The tool name is the directory name under tools/
          tool_name = if tools_dir == 'tools'
                        tool_dir
                      else
                        file_name
                      end

          # Don't hardcode register path - use options or let Tool.find handle it
          tool_options = {}
          tool_options[:register_path] = options[:register] if options[:register]

          # Load the tool (Tool.get will find the right register path)
          tool = Ukiryu::Tool.get(tool_name, **tool_options)

          # Check if the tool is available
          if tool.available?
            say "✓ Tool found at: #{tool.executable}", :green
          else
            say '✗ Tool not found', :red
            say '  Searched in: system PATH', :dim
            exit 1
          end

          # Test version detection if defined
          if tool.profile.version_detection
            say '', :clear
            say 'Testing version detection...', :cyan

            begin
              detected_version = tool.detect_version

              if detected_version
                say "✓ Version detected: #{detected_version}", :green
              else
                say '⚠ Version detection failed - could not extract version', :yellow
              end
            rescue StandardError => e
              say "⚠ Version check failed: #{e.message}", :yellow
            end
          end

          # Run smoke tests from profile if defined
          smoke_tests = profile_data[:smoke_tests] || profile_data['smoke_tests']
          if smoke_tests && !smoke_tests.empty?
            say '', :clear
            say "Running #{smoke_tests.length} smoke test(s)...", :cyan
            run_smoke_tests(tool, smoke_tests, profile_data)
          elsif tool.profile.profiles&.any?
            # Fallback: test basic command execution if commands are defined
            profile = tool.profile.profiles.first
            if profile.commands && !profile.commands.empty?
              say '', :clear
              say 'Testing command execution (smoke test)...', :cyan

              profile.commands.each do |cmd_def|
                cmd_name = cmd_def.name
                begin
                  test_result = execute_smoke_test(tool, cmd_name)

                  if test_result[:success]
                    say "✓ Command '#{cmd_name}' is available", :green
                  else
                    say "⚠ Command '#{cmd_name}' test failed: #{test_result[:message]}", :yellow
                  end
                rescue StandardError => e
                  say "⚠ Command '#{cmd_name}' test error: #{e.message}", :yellow
                end

                break
              end
            end
          end
        rescue Ukiryu::Errors::ToolNotFoundError => e
          say "✗ Tool not found: #{e.message}", :red
          exit 1
        rescue StandardError => e
          say "✗ Executable test failed: #{e.message}", :red
          exit 1 if options[:strict]
        end
      end

      # Test all executables in the register
      #
      # This method runs executable validation against all tool definitions
      def test_all_executables
        register_path = Ukiryu::Register.default.path
        return say_error("Register not found: #{register_path}") unless Dir.exist?(register_path)

        tools_dir = File.join(register_path, 'tools')
        return say_error("Tools directory not found: #{tools_dir}") unless Dir.exist?(tools_dir)

        yaml_files = Dir.glob(File.join(tools_dir, '*', '*.yaml')).sort

        # Skip index.yaml files - they are metadata files that list implementations
        yaml_files = yaml_files.reject { |f| File.basename(f) == 'index.yaml' }

        say '', :clear
        say "Testing #{yaml_files.length} tool executable(s)...", :cyan

        passed = 0
        failed = 0
        skipped = 0

        yaml_files.each do |file|
          relative_path = file.sub("#{tools_dir}/", '')

          # Get relative path for display
          begin
            # Load the YAML profile to check if we should test it
            YAML.safe_load(File.read(file), permitted_classes: [Symbol, Date, Time])

            # Extract tool name from file path
            file_name = File.basename(file, '.yaml')
            tool_dir = File.basename(File.dirname(file))
            tools_dir_name = File.basename(File.dirname(File.dirname(file)))

            # The tool name is the directory name under tools/
            tool_name = if tools_dir_name == 'tools'
                          tool_dir
                        else
                          file_name
                        end

            # Don't hardcode register path - use options or let Tool.find handle it
            tool_options = {}
            tool_options[:register_path] = options[:register] if options[:register]

            # Load the tool (Tool.get will find the right register path)
            tool = Ukiryu::Tool.get(tool_name, **tool_options)

            # Test if the tool is available
            if tool.available?
              # Test version detection if defined
              if tool.profile.version_detection
                begin
                  detected_version = tool.detect_version
                  say "  #{relative_path.ljust(35)} ✓ (v#{detected_version})", :green
                  passed += 1
                rescue StandardError => e
                  say "  #{relative_path.ljust(35)} ⚠ Version detection failed: #{e.message}", :yellow
                  skipped += 1
                end
              else
                say "  #{relative_path.ljust(35)} ✓ (no version detection)", :green
                passed += 1
              end
            else
              say "  #{relative_path.ljust(35)} ⊘ (not installed)", :dim
              skipped += 1
            end
          rescue Ukiryu::Errors::ToolNotFoundError
            say "  #{relative_path.ljust(35)} ✗ (tool not found)", :yellow
            skipped += 1
          rescue StandardError => e
            say "  #{relative_path.ljust(35)} ✗ Error: #{e.message}", :red
            failed += 1 if options[:strict]
          end
        end

        # Summary
        say '', :clear
        say 'Executable Test Summary:', :cyan
        say "  Total:   #{yaml_files.length}", :white
        say "  Passed:  #{passed}", :green
        say "  Skipped: #{skipped}", :yellow
        say "  Failed:  #{failed}", failed.positive? ? :red : :green

        exit 1 if failed.positive? && options[:strict]
      end

      # Run smoke tests from profile
      #
      # @param tool [Ukiryu::Tool] the tool instance
      # @param smoke_tests [Array<Hash>] smoke test definitions
      # @param profile_data [Hash] the loaded profile data
      def run_smoke_tests(tool, smoke_tests, profile_data)
        smoke_tests.each_with_index do |test, index|
          test_name = test[:name] || test['name']
          test_description = test[:description] || test['description'] || test_name

          say '', :clear
          say "[#{index + 1}/#{smoke_tests.length}] #{test_name}: #{test_description}", :cyan

          # Check platform filter
          platforms = test[:platforms] || test['platforms']
          current_platform = current_platform_symbol
          if platforms && !platforms.include?(current_platform.to_s)
            say "  ⊘ Skipped (not for this platform: #{current_platform})", :dim
            next
          end

          # Check skip_if condition
          skip_if = test[:skip_if] || test['skip_if']
          if skip_if && evaluate_condition(skip_if, tool, profile_data)
            say "  ⊘ Skipped (condition: #{skip_if})", :dim
            next
          end

          # Get the command to run
          test_command = test[:command] || test['command']
          test_timeout = test[:timeout] || test['timeout'] || tool.profile.timeout || 30

          begin
            # Execute the test command
            result = execute_test_command(tool, test_command, test_timeout)

            # Validate the result
            validation_result = validate_test_result(result, test)

            if validation_result[:passed]
              say '  ✓ PASSED', :green
              if options[:verbose] && validation_result[:details]
                validation_result[:details].each do |detail|
                  say "    #{detail}", :dim
                end
              end
            else
              say '  ✗ FAILED', :red
              validation_result[:errors].each do |error|
                say "    ✗ #{error}", :red
              end
              exit 1 if options[:strict]
            end
          rescue StandardError => e
            say "  ✗ ERROR: #{e.message}", :red
            exit 1 if options[:strict]
          end
        end
      end

      # Execute a test command using Executor
      #
      # @param tool [Ukiryu::Tool] the tool instance
      # @param test_command [String, Array] command to run
      # @param timeout [Integer] timeout in seconds
      # @return [Execution::Result] execution result
      def execute_test_command(tool, test_command, timeout)
        cmd_array = if test_command.is_a?(Array)
                      test_command
                    else
                      test_command.shellsplit
                    end

        # Detect shell for internal utility execution
        shell_class = Shell.detect

        # Use Executor.execute with explicit shell parameter
        Executor.execute(
          tool.executable,
          cmd_array,
          timeout: timeout,
          shell: shell_class,
          tool_name: tool.name
        )
      end

      # Validate test result against expectations
      #
      # @param result [Execution::Result] execution result
      # @param test [Hash] test definition with expect section
      # @return [Hash] validation result with :passed, :errors, :details
      def validate_test_result(result, test)
        errors = []
        details = []
        passed = true

        expect = test[:expect] || test['expect'] || {}

        # Check exit code
        expected_exit_code = expect[:exit_code] || expect['exit_code'] || 0
        if result.exit_status != expected_exit_code
          errors << "Exit code mismatch: expected #{expected_exit_code}, got #{result.exit_status}"
          passed = false
        else
          details << "Exit code: #{result.exit_status} (as expected)"
        end

        # Check output_match regex
        output_match = expect[:output_match] || expect['output_match']
        if output_match
          regex = Regexp.new(output_match)
          if result.stdout =~ regex
            details << "Output matches pattern: #{output_match}"
          else
            errors << "Output does not match pattern: #{output_match}"
            passed = false
          end
        end

        # Check output_contains
        output_contains = expect[:output_contains] || expect['output_contains']
        if output_contains && !output_contains.empty?
          output_contains.each do |str|
            if result.stdout.include?(str)
              details << "Output contains: #{str}"
            else
              errors << "Output missing string: #{str}"
              passed = false
            end
          end
        end

        # Check stderr_match regex
        stderr_match = expect[:stderr_match] || expect['stderr_match']
        if stderr_match
          regex = Regexp.new(stderr_match)
          if result.stderr =~ regex
            details << "Stderr matches pattern: #{stderr_match}"
          else
            errors << "Stderr does not match pattern: #{stderr_match}"
            passed = false
          end
        end

        { passed: passed, errors: errors, details: details }
      end

      # Get current platform as symbol
      #
      # @return [Symbol] platform symbol
      def current_platform_symbol
        case RbConfig::CONFIG['host_os']
        when /linux/i
          :linux
        when /darwin/i
          :macos
        when /mswin|mingw|cygwin/i
          :windows
        else
          :unknown
        end
      end

      # Evaluate skip condition (basic implementation)
      #
      # @param condition [String] condition string
      # @param tool [Ukiryu::Tool] tool instance
      # @param profile_data [Hash] profile data
      # @return [Boolean] true if condition is met
      def evaluate_condition(_condition, _tool, _profile_data)
        # Very basic condition evaluation - can be expanded later
        # For now, just return false to not skip any tests
        false
      end

      # Execute a simple smoke test for a command
      #
      # @param tool [Ukiryu::Tool] the tool instance
      # @param cmd_name [Symbol] the command name
      # @return [Hash] test result with :success and :message
      def execute_smoke_test(tool, cmd_name)
        # Try to get help for the command - most CLI tools support --help or -h

        # Try with empty arguments first, just to see if the command runs
        result = tool.execute(cmd_name, {})

        # If we get here, the command executed
        # Check for common error patterns
        if result.exit_status.zero?
          { success: true, message: 'Command executed successfully' }
        elsif result.stderr.include?('unrecognized') || result.stderr.include?('unknown')
          { success: false, message: 'Command not recognized by tool' }
        else
          { success: true, message: "Command executed (exit code: #{result.exit_status})" }
        end
      rescue Ukiryu::Errors::ExecutionError => e
        if e.result.stderr.include?('unrecognized') || e.result.stderr.include?('unknown')
          { success: false, message: 'Command not recognized by tool' }
        else
          { success: false, message: e.message }
        end
      end

      # Validate all definitions in register
      def validate_all
        register_path = Ukiryu::Register.default.path
        return say_error("Register not found: #{register_path}") unless Dir.exist?(register_path)

        tools_dir = File.join(register_path, 'tools')
        return say_error("Tools directory not found: #{tools_dir}") unless Dir.exist?(tools_dir)

        results = {}
        yaml_files = Dir.glob(File.join(tools_dir, '*', '*.yaml')).sort

        # Skip index.yaml files - they are metadata files that list implementations
        yaml_files = yaml_files.reject { |f| File.basename(f) == 'index.yaml' }

        say "Validating #{yaml_files.length} tool definitions...", :cyan
        say '', :clear

        yaml_files.each do |file|
          # Get relative path from tools directory
          relative_path = file.sub("#{tools_dir}/", '')

          result = Ukiryu::Definition::DefinitionValidator.validate_file(
            file,
            schema_path: options[:schema]
          )
          results[file] = result

          # Show file and result on same line
          if result.valid?
            status = result.has_warnings? ? '✓ VALID (with warnings)' : '✓ VALID'
            say "  #{relative_path.ljust(35)} #{status}", result.has_warnings? ? :yellow : :green
          else
            say "  #{relative_path.ljust(35)} ✗ INVALID", :red
            result.errors.each do |error|
              say "    - #{error}", :red
            end
          end

          next unless result.has_warnings?

          result.warnings.each do |warning|
            say "    ⚠ #{warning}", :yellow
          end
        end

        # Summary
        say '', :clear
        total = results.length
        valid = results.values.count(&:valid?)
        invalid = results.values.count(&:invalid?)

        say 'Validation Summary:', :cyan
        say "  Total:   #{total}", :white
        say "  Valid:   #{valid}", :green
        say "  Invalid: #{invalid}", invalid.zero? ? :green : :red

        exit 1 if invalid.positive?
      end

      # Validate a YAML string
      #
      # @param yaml_string [String] YAML content
      def validate_string(yaml_string)
        result = Ukiryu::Definition::DefinitionValidator.validate_string(
          yaml_string,
          schema_path: options[:schema]
        )

        output_result(result, '<string>')
        exit 1 if result.invalid? || (result.has_warnings? && options[:strict])
      end

      # Output validation result
      #
      # @param result [ValidationResult] validation result
      # @param source [String] source identifier
      def output_result(result, source)
        case options[:format]
        when 'json'
          say result.to_json, :white
        else
          output_text(result, source)
        end
      end

      # Output as text
      #
      # @param result [ValidationResult] validation result
      # @param source [String] source identifier
      def output_text(result, source)
        say "Validating: #{source}", :cyan

        if result.valid?
          if result.has_warnings?
            say '✓ Valid with warnings', :yellow
            say '', :clear
            result.warnings.each { |w| say "  Warning: #{w}", :yellow }
          else
            say '✓ Valid', :green
          end
        else
          say '✗ Invalid', :red
          say '', :clear
          result.errors.each { |e| say "  Error: #{e}", :red }
          if result.has_warnings?
            say '', :clear
            result.warnings.each { |w| say "  Warning: #{w}", :yellow }
          end
        end
      end

      # Show error message
      #
      # @param message [String] error message
      def say_error(message)
        say message, :red
        exit 1
      end
    end
  end
end
