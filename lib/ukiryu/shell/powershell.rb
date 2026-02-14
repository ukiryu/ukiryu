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
      # Uses Start-Process to avoid PowerShell's parameter binder stripping
      # dash-prefixed arguments. The call operator (&) in PowerShell still
      # interprets arguments starting with - as parameters even when quoted,
      # causing -sDEVICE=pdfwrite to become =pdfwrite.
      #
      # Start-Process with -ArgumentList passes arguments verbatim without
      # any parameter binding interference.
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

        # Build arguments array for Start-Process -ArgumentList
        # ALL arguments must be quoted consistently for the PowerShell array literal
        args_escaped = args.map do |a|
          # Debug logging
          if ENV['UKIRYU_DEBUG_EXECUTABLE']
            warn "[UKIRYU DEBUG PowerShell#execute_command] escaping arg: #{a.inspect}"
          end
          # Escape special characters for double-quoted strings in PowerShell
          # Backticks and dollar signs need escaping with backtick
          escaped = a.to_s.gsub(/[`$]/) { "`#{::Regexp.last_match(0)}" }.gsub('"', '`"')
          result = %("#{escaped}")
          if ENV['UKIRYU_DEBUG_EXECUTABLE']
            warn "[UKIRYU DEBUG PowerShell#execute_command] escaped to: #{result.inspect}"
          end
          result
        end

        # Build the argument list string
        arg_list = args_escaped.join(', ')
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG PowerShell#execute_command] arg_list: #{arg_list.inspect}"
        end

        # Build PowerShell command using Start-Process
        # This avoids the call operator's parameter binding issues
        exe_escaped = executable.to_s.gsub('"', '`"')

        ps_command = if args.empty?
                       <<~PS.strip
                         $p = Start-Process -FilePath "#{exe_escaped}" -NoNewWindow -Wait -PassThru
                         exit $p.ExitCode
                       PS
                     else
                       <<~PS.strip
                         $p = Start-Process -FilePath "#{exe_escaped}" -ArgumentList @(#{arg_list}) -NoNewWindow -Wait -PassThru
                         exit $p.ExitCode
                       PS
                     end

        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG PowerShell#execute_command] ps_command:\n#{ps_command}"
        end

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
      # Uses Start-Process with -RedirectStandardInput for stdin handling.
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
        # Build arguments for Start-Process -ArgumentList
        # ALL arguments must be quoted consistently
        args_escaped = args.map do |a|
          escaped = a.to_s.gsub(/[`$]/) { "`#{::Regexp.last_match(0)}" }.gsub('"', '`"')
          %("#{escaped}")
        end
        arg_list = args_escaped.join(', ')

        exe_escaped = executable.to_s.gsub('"', '`"')

        # Write stdin to temp file for redirection
        stdin_file = Tempfile.new('ukiryu_stdin')
        begin
          if stdin_data.is_a?(IO)
            IO.copy_stream(stdin_data, stdin_file)
          elsif stdin_data.is_a?(String)
            stdin_file.write(stdin_data)
          end
          stdin_file.close

          stdin_path = stdin_file.path.gsub('\\', '\\\\').gsub('"', '`"')

          ps_command = if args.empty?
                         <<~PS.strip
                           $p = Start-Process -FilePath "#{exe_escaped}" -NoNewWindow -Wait -PassThru -RedirectStandardInput "#{stdin_path}"
                           exit $p.ExitCode
                         PS
                       else
                         <<~PS.strip
                           $p = Start-Process -FilePath "#{exe_escaped}" -ArgumentList @(#{arg_list}) -NoNewWindow -Wait -PassThru -RedirectStandardInput "#{stdin_path}"
                           exit $p.ExitCode
                         PS
                       end

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
