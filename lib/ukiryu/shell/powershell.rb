# frozen_string_literal: true

require 'open3'
require 'timeout'
require 'tempfile'

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
      # - Single quotes are escaped by doubling them (for single-quoted strings)
      # - Backtick, dollar, and double quotes are escaped with backtick (for double-quoted strings)
      #
      # Note: This method escapes for single-quoted strings by default since we use
      # single quotes for arguments to prevent parameter binding issues.
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        # For single-quoted strings, escape single quotes by doubling them
        string.to_s.gsub("'", "''")
      end

      # Escape a string for double-quoted PowerShell strings
      # Used for executable paths which need double quotes
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape_for_double_quotes(string)
        string.to_s.gsub(/[`"$]/) { "`#{::Regexp.last_match(0)}" }
      end

      # Check if a string needs quoting for PowerShell
      # Overrides base class to add PowerShell-specific handling
      #
      # In PowerShell, arguments starting with - are interpreted as PowerShell
      # parameters when passed to the call operator (&). This causes the prefix
      # to be stripped (e.g., -sDEVICE=pdfwrite becomes =pdfwrite).
      # To prevent this, we must quote all arguments starting with -.
      #
      # Also, arguments containing $ must be quoted to prevent variable expansion.
      #
      # @param string [String] the string to check
      # @return [Boolean] true if quoting is needed
      def needs_quoting?(string)
        str = string.to_s
        # Call super for base checks (empty, whitespace, special chars)
        return true if super(string)
        # PowerShell-specific: arguments starting with - must be quoted
        # to prevent PowerShell's parameter binder from stripping the prefix
        return true if str.start_with?('-')
        # PowerShell-specific: arguments containing $ must be quoted
        # to prevent variable expansion
        return true if str.include?('$')

        false
      end

      # Quote an argument for PowerShell
      # Uses double quotes for all arguments to prevent PowerShell's parameter
      # binder from stripping dash prefixes. Double quotes work consistently
      # across both the call operator (&) and Start-Process.
      #
      # @param string [String] the string to quote
      # @param for_exe [Boolean] true if quoting for executable path (same behavior)
      # @return [String] the quoted string
      def quote(string, for_exe: false)
        # Always use double quotes - this prevents PowerShell's parameter binder
        # from stripping dash prefixes in all contexts (call operator, Start-Process)
        "\"#{escape_for_double_quotes(string)}\""
      end

      # Format an environment variable reference
      #
      # @param name [String] the variable name
      # @return [String] the formatted reference ($ENV:NAME)
      def env_var(name)
        "$ENV:#{name}"
      end

      # Format a file path for PowerShell on Windows
      #
      # Returns the path unchanged. Quoting for paths with spaces is handled
      # by the quote method, which wraps paths in double quotes with proper
      # escaping.
      #
      # @param path [String] the file path
      # @return [String] the formatted path
      def format_path(path)
        path.to_s
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
        # Debug logging for CI - helps identify where prefix stripping might occur
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG PowerShell#join] executable: #{executable.inspect}"
          warn "[UKIRYU DEBUG PowerShell#join] args: #{args.inspect}"
          warn "[UKIRYU DEBUG PowerShell#join] args.size: #{args.size}"
          warn "[UKIRYU DEBUG PowerShell#join] args.class: #{args.class}"
          args.each_with_index do |a, i|
            warn "[UKIRYU DEBUG PowerShell#join] args[#{i}]: #{a.inspect} (#{a.class})"
            # Check for nested arrays which would cause stringification issues
            if a.is_a?(Array)
              warn "[UKIRYU DEBUG PowerShell#join] WARNING: args[#{i}] is a NESTED ARRAY!"
              warn "[UKIRYU DEBUG PowerShell#join] This will be converted to string: #{a.to_s.inspect}"
            end
          end
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
      # On Windows: Uses cmd /c to execute commands. This provides more predictable
      # quoting behavior than PowerShell's Start-Process for native executables
      # with arguments containing spaces.
      #
      # On Unix: Uses the call operator (&) since PowerShell on Unix doesn't have
      # the parameter binding issues that Windows PowerShell has.
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command(executable, args, env, timeout, cwd = nil)
        # Debug logging for CI - helps identify where prefix stripping might occur
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG PowerShell#execute_command] executable: #{executable.inspect}"
          warn "[UKIRYU DEBUG PowerShell#execute_command] args: #{args.inspect}"
          warn "[UKIRYU DEBUG PowerShell#execute_command] args.class: #{args.class}"
          args.each_with_index do |a, i|
            warn "[UKIRYU DEBUG PowerShell#execute_command] args[#{i}]: #{a.inspect} (#{a.class})"
            # Check for nested arrays which would cause stringification issues
            warn "[UKIRYU DEBUG PowerShell#execute_command] WARNING: args[#{i}] is a NESTED ARRAY!" if a.is_a?(Array)
          end
        end

        # Build the command line with proper quoting
        if Platform.windows?
          # On Windows: Use PowerShell call operator with single quotes for all arguments
          # Single quotes are completely literal in PowerShell - no parameter binding issues
          # This works for both paths with spaces and without spaces
          exe_normalized = executable.to_s.gsub('/', '\\')
          exe_escaped = exe_normalized.gsub("'", "''")

          args_escaped = args.map do |a|
            arg_str = a.to_s.gsub('/', '\\')
            if arg_str.start_with?('-')
              # Arguments starting with - must be single-quoted to prevent PowerShell's
              # parameter binder from stripping the prefix (e.g., -sDEVICE=pdfwrite -> =pdfwrite)
              escaped = arg_str.gsub("'", "''")
              "'#{escaped}'"
            elsif arg_str.include?('$') || arg_str.include?('`')
              # Use single quotes for arguments with $ or ` to prevent expansion
              escaped = arg_str.gsub("'", "''")
              "'#{escaped}'"
            elsif arg_str.include?(' ') || arg_str.include?('"')
              # Use single quotes for spaces or quotes (completely literal)
              escaped = arg_str.gsub("'", "''")
              "'#{escaped}'"
            else
              arg_str
            end
          end

          # Propagate exit code from external command using $LASTEXITCODE
        else
          # On Unix: Use the call operator directly with single quotes
          # Single quotes are completely literal in PowerShell (no variable expansion)
          exe_escaped = executable.to_s.gsub("'", "''")

          args_escaped = args.map do |a|
            arg_str = a.to_s
            # Quote arguments that contain special PowerShell characters or
            # start with dash (to prevent parameter binding)
            if arg_str.include?(' ') || arg_str.start_with?('-') || arg_str.include?('$') || arg_str.include?('`') || arg_str.include?(';')
              # Use single quotes for completely literal strings
              escaped = arg_str.gsub("'", "''")
              "'#{escaped}'"
            else
              arg_str
            end
          end

          # Propagate exit code from external command using $LASTEXITCODE
        end
        full_command = ["'#{exe_escaped}'", *args_escaped].join(' ')
        warn "[UKIRYU DEBUG PowerShell#execute_command] full_command: #{full_command.inspect}" if ENV['UKIRYU_DEBUG_EXECUTABLE']
        ps_command = "& #{full_command}; exit $LASTEXITCODE"

        warn "[UKIRYU DEBUG PowerShell#execute_command] ps_command:\n#{ps_command}" if ENV['UKIRYU_DEBUG_EXECUTABLE']

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
      # Uses platform-specific execution with stdin redirection.
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
        # Write stdin to temp file for redirection
        stdin_file = Tempfile.new('ukiryu_stdin')
        begin
          if stdin_data.is_a?(IO)
            IO.copy_stream(stdin_data, stdin_file)
          elsif stdin_data.is_a?(String)
            stdin_file.write(stdin_data)
          end
          stdin_file.close

          stdin_path = stdin_file.path

          if Platform.windows?
            # On Windows: Use PowerShell call operator with single quotes for all arguments
            # Single quotes are completely literal in PowerShell - no parameter binding issues
            # This works for both paths with spaces and without spaces
            exe_normalized = executable.to_s.gsub('/', '\\')
            exe_escaped = exe_normalized.gsub("'", "''")

            args_escaped = args.map do |a|
              arg_str = a.to_s.gsub('/', '\\')
              if arg_str.start_with?('-')
                # Arguments starting with - must be single-quoted to prevent PowerShell's
                # parameter binder from stripping the prefix (e.g., -sDEVICE=pdfwrite -> =pdfwrite)
                escaped = arg_str.gsub("'", "''")
                "'#{escaped}'"
              elsif arg_str.include?('$') || arg_str.include?('`')
                # Use single quotes for arguments with $ or ` to prevent expansion
                escaped = arg_str.gsub("'", "''")
                "'#{escaped}'"
              elsif arg_str.include?(' ') || arg_str.include?('"')
                # Use single quotes for spaces or quotes (completely literal)
                escaped = arg_str.gsub("'", "''")
                "'#{escaped}'"
              else
                arg_str
              end
            end

            # Propagate exit code from external command using $LASTEXITCODE
          else
            # On Unix: Use the call operator with stdin redirection
            # Single quotes are completely literal in PowerShell (no variable expansion)
            exe_escaped = executable.to_s.gsub("'", "''")

            args_escaped = args.map do |a|
              arg_str = a.to_s
              # Quote arguments that contain special PowerShell characters or
              # start with dash (to prevent parameter binding)
              if arg_str.include?(' ') || arg_str.start_with?('-') || arg_str.include?('$') || arg_str.include?('`') || arg_str.include?(';')
                escaped = arg_str.gsub("'", "''")
                "'#{escaped}'"
              else
                arg_str
              end
            end

            # Use Get-Content to read stdin file and pipe to command
            # Propagate exit code from external command using $LASTEXITCODE
          end
          full_command = ["'#{exe_escaped}'", *args_escaped].join(' ')
          ps_command = "Get-Content '#{stdin_path.gsub("'", "''")}' | & #{full_command}; exit $LASTEXITCODE"

          env_hash = environment_to_h(env)

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
        ensure
          stdin_file.unlink
        end
      rescue Timeout::Error, Timeout::ExitException
        raise Timeout::Error, "Command timed out after #{timeout}s: #{executable}"
      end
    end
  end
end
