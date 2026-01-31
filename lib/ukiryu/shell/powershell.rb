# frozen_string_literal: true

require 'open3'
require 'timeout'

module Ukiryu
  module Shell
    # PowerShell shell implementation
    #
    # PowerShell uses single quotes for literal strings and backtick
    # for escaping special characters inside double quotes.
    # Environment variables are referenced with $ENV:NAME syntax.
    class PowerShell < Base
      SHELL_NAME = :powershell
      PLATFORM = :powershell
      EXECUTABLE = 'pwsh'

      # Detect if a command is a PowerShell alias
      #
      # PowerShell has aliases but they are PowerShell-level constructs, not shell aliases.
      # We don't detect PowerShell aliases for executable discovery.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] always returns nil (no alias detection)
      def self.detect_alias(_command_name)
        # PowerShell aliases are runtime constructs, not shell aliases
        # They don't help with executable discovery
        nil
      end

      def name
        :powershell
      end

      # Get the PowerShell executable for the current platform
      # On Windows: powershell.exe
      # On Unix/macOS: pwsh (PowerShell Core)
      #
      # @return [String] the PowerShell executable command
      def powershell_command
        Platform.windows? ? 'powershell' : 'pwsh'
      end

      # Escape a string for PowerShell
      # Backtick is the escape character for: ` $ "
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        string.to_s.gsub(/[`"$]/) { "`#{::Regexp.last_match(0)}" }
      end

      # Quote an argument for PowerShell
      # Uses single quotes for literal strings
      # Uses double quotes for executable paths (works in both cmd.exe and PowerShell)
      #
      # @param string [String] the string to quote
      # @param for_exe [Boolean] true if quoting for executable path
      # @return [String] the quoted string
      def quote(string, for_exe: false)
        if for_exe
          # For executable paths, use double quotes which work in both cmd.exe and PowerShell
          # This is needed because Ruby's Open3 uses cmd.exe on Windows, not PowerShell
          "\"#{string}\""
        else
          # For arguments, use single quotes for literal strings
          "'#{escape(string)}'"
        end
      end

      # Format an environment variable reference
      #
      # @param name [String] the variable name
      # @return [String] the formatted reference ($ENV:NAME)
      def env_var(name)
        "$ENV:#{name}"
      end

      # Join executable and arguments into a command line
      # Uses smart quoting: only quote arguments that need it
      #
      # Special handling for -Command and -File: The argument after these
      # parameters should NOT be quoted because PowerShell will parse it
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @return [String] the complete command line
      def join(executable, *args)
        # Debug logging for Ruby 4.0 CI
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG PowerShell#join] executable: #{executable.inspect}"
          warn "[UKIRYU DEBUG PowerShell#join] args: #{args.inspect}"
          warn "[UKIRYU DEBUG PowerShell#join] args.size: #{args.size}"
          warn "[UKIRYU DEBUG PowerShell#join] args.class: #{args.class}"
        end

        # Quote executable if it needs quoting (e.g., contains spaces)
        # Use double quotes for executables (works in both cmd.exe and PowerShell)
        # Ruby's Open3 on Windows uses cmd.exe, not PowerShell
        exe_formatted = needs_quoting?(executable) ? quote(executable, for_exe: true) : executable

        # Track when we see -Command or -File to skip quoting the next argument
        skip_quote = false
        args_formatted = args.map do |a|
          if skip_quote
            # Don't quote the script/file argument - PowerShell will parse it
            skip_quote = false
            a
          elsif ['-Command', '-File'].include?(a)
            skip_quote = true
            a
          elsif needs_quoting?(a)
            quote(a)
          else
            # For simple strings, pass without quotes
            # PowerShell treats them as literal strings
            a
          end
        end
        [exe_formatted, *args_formatted].join(' ')
      end

      # PowerShell doesn't need DISPLAY variable
      #
      # @return [Hash] empty hash (no headless environment needed)
      def headless_environment
        {}
      end

      # PowerShell capabilities on Windows
      #
      # @return [Hash] capability flags
      def capabilities
        {
          supports_display: false, # Windows doesn't use DISPLAY
          supports_ansi_colors: true,
          encoding: Encoding::UTF_8 # PowerShell uses UTF-8
        }
      end

      # Execute a command using PowerShell
      #
      # Uses PowerShell's -Command flag to execute the command string.
      # The executable and arguments are quoted individually and passed to
      # PowerShell's call operator &.
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command(executable, args, env, timeout, cwd = nil)
        # Build the command with proper quoting for each element
        # Use double quotes for PowerShell -Command (works better than single quotes)
        exe_quoted = %("#{escape(executable)}")

        # Quote each argument - only quote if it contains special chars or spaces
        args_quoted = args.map do |a|
          if needs_quoting?(a)
            %("#{escape(a)}")
          else
            a
          end
        end

        # Build PowerShell command: & "executable" "arg1" "arg2" ...
        # Append "; exit $LASTEXITCODE" to properly propagate exit codes from
        # the invoked command/program back through the PowerShell wrapper
        ps_command_base = if args_quoted.empty?
                            "& #{exe_quoted}"
                          else
                            "& #{exe_quoted} #{args_quoted.join(' ')}"
                          end
        ps_command = "#{ps_command_base}; exit $LASTEXITCODE"

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using PowerShell's -Command flag
        Timeout.timeout(timeout) do
          execution = lambda do
            stdout, stderr, status = Open3.capture3(env_hash, powershell_command, '-NoLogo', '-Command', ps_command)
            {
              status: Ukiryu::Executor.extract_status(status),
              stdout: stdout,
              stderr: stderr
            }
          end

          if cwd
            Dir.chdir(cwd) { execution.call }
          else
            execution.call
          end
        end
      rescue Timeout::Error, Timeout::ExitException
        # Re-raise with context
        raise Timeout::Error, "Command timed out after #{timeout}s: #{executable}"
      end

      # Execute a command with stdin input using PowerShell
      #
      # Uses PowerShell's -Command flag to execute the command string.
      # The executable and arguments are quoted individually and passed to
      # PowerShell's call operator &.
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @param stdin_data [String, IO] stdin input data
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command_with_stdin(executable, args, env, timeout, cwd, stdin_data)
        # Build the command with proper quoting for each element
        # Use double quotes for PowerShell -Command (works better than single quotes)
        exe_quoted = %("#{escape(executable)}")

        # Quote each argument - only quote if it contains special chars or spaces
        args_quoted = args.map do |a|
          if needs_quoting?(a)
            %("#{escape(a)}")
          else
            a
          end
        end

        # Build PowerShell command: & "executable" "arg1" "arg2" ...
        # Append "; exit $LASTEXITCODE" to properly propagate exit codes from
        # the invoked command/program back through the PowerShell wrapper
        ps_command_base = if args_quoted.empty?
                            "& #{exe_quoted}"
                          else
                            "& #{exe_quoted} #{args_quoted.join(' ')}"
                          end
        ps_command = "#{ps_command_base}; exit $LASTEXITCODE"

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using PowerShell's -Command flag
        Timeout.timeout(timeout) do
          execution = lambda do
            Open3.popen3(env_hash, powershell_command, '-NoLogo', '-Command',
                         ps_command) do |stdin, stdout, stderr, wait_thr|
              # Write stdin data
              begin
                if stdin_data.is_a?(IO)
                  IO.copy_stream(stdin_data, stdin)
                elsif stdin_data.is_a?(String)
                  stdin.write(stdin_data)
                end
              rescue Errno::EPIPE
                # Process closed stdin early
              ensure
                stdin.close
              end

              # Read output
              out = stdout.read
              err = stderr.read

              # Wait for process to complete
              status = wait_thr.value

              {
                status: Ukiryu::Executor.extract_status(status),
                stdout: out,
                stderr: err
              }
            end
          end

          if cwd
            Dir.chdir(cwd) { execution.call }
          else
            execution.call
          end
        end
      rescue Timeout::Error, Timeout::ExitException
        # Re-raise with context
        raise Timeout::Error, "Command timed out after #{timeout}s: #{executable}"
      end
    end
  end
end
