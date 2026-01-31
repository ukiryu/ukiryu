# frozen_string_literal: true

require 'open3'
require 'timeout'

module Ukiryu
  module Shell
    # Windows cmd.exe shell implementation
    #
    # cmd.exe uses caret (^) as the escape character and double quotes
    # for strings containing spaces. Environment variables use %VAR% syntax.
    class Cmd < Base
      SHELL_NAME = :cmd
      PLATFORM = :windows
      EXECUTABLE = 'cmd'

      # Pre-compiled pattern for whitespace detection
      WHITESPACE_PATTERN = /[ \t]/.freeze

      # Detect if a command is a cmd.exe alias
      #
      # cmd.exe has doskey macros but they are not traditional shell aliases.
      # We don't detect doskey macros for executable discovery.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] always returns nil (no alias detection)
      def self.detect_alias(_command_name)
        # cmd.exe doskey macros are not shell aliases in the Unix sense
        nil
      end

      def name
        :cmd
      end

      # Escape a string for cmd.exe
      # Caret is the escape character for special characters: % ^ < > & |
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        string.to_s.gsub(/[%^<>&|]/) { "^#{::Regexp.last_match(0)}" }
      end

      # Quote an argument for cmd.exe
      # Uses double quotes for strings with spaces
      #
      # @param string [String] the string to quote
      # @return [String] the quoted string
      def quote(string)
        if string.to_s =~ WHITESPACE_PATTERN
          # Contains whitespace, use double quotes
          # Note: cmd.exe doesn't escape quotes inside double quotes the same way
          "\"#{string}\""
        else
          # No whitespace, escape special characters
          escape(string)
        end
      end

      # Format a file path for cmd.exe
      # Convert forward slashes to backslashes
      #
      # @param path [String] the file path
      # @return [String] the formatted path
      def format_path(path)
        path.to_s.gsub('/', '\\')
      end

      # Format an environment variable reference
      #
      # @param name [String] the variable name
      # @return [String] the formatted reference (%VAR%)
      def env_var(name)
        "%#{name}%"
      end

      # Join executable and arguments into a command line
      # Uses smart quoting: only quote arguments that need it
      #
      # Special handling for /c: When using cmd.exe's /c flag, the command
      # string that follows should NOT be quoted, as cmd.exe treats it as a
      # single command to execute. The quotes become literal characters.
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @return [String] the complete command line
      def join(executable, *args)
        # Quote executable if it needs quoting (e.g., contains spaces)
        exe_formatted = needs_quoting?(executable) ? quote(executable) : escape(executable)

        # Special handling for cmd.exe /c flag
        # When using /c, the rest is a single command string - don't quote it
        if args[0] == '/c' && args.length > 1
          # Build command string from the remaining arguments
          # They form a single command that cmd.exe will execute
          command_parts = args[1..]
          # For the command string, we escape special chars but don't wrap in quotes
          # This allows cmd.exe to parse operators like &&, |, etc.
          command_string = command_parts.map { |a| escape(a) }.join(' ')
          [exe_formatted, args[0], command_string].join(' ')
        else
          # Normal quoting for all arguments
          args_formatted = args.map do |a|
            if needs_quoting?(a)
              quote(a)
            else
              # For simple strings, pass without quotes
              # cmd.exe treats them as literal strings
              escape(a)
            end
          end
          [exe_formatted, *args_formatted].join(' ')
        end
      end

      # cmd.exe doesn't need DISPLAY variable
      #
      # @return [Hash] empty hash (no headless environment needed)
      def headless_environment
        {}
      end

      # cmd.exe capabilities on Windows
      #
      # @return [Hash] capability flags
      def capabilities
        {
          supports_display: false, # Windows doesn't use DISPLAY
          supports_ansi_colors: true,
          encoding: Encoding::CP_1252 # cmd.exe default is CP1252 (Windows-1252)
        }
      end

      # Execute a command using cmd.exe
      #
      # Uses cmd.exe's /c flag to execute the command string.
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command(executable, args, env, timeout, cwd = nil)
        # Build command string using this shell's quoting rules
        command_string = join(executable, *args)

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using cmd.exe's /c flag
        Timeout.timeout(timeout) do
          execution = lambda do
            stdout, stderr, status = Open3.capture3(env_hash, 'cmd', '/c', command_string)
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

      # Execute a command with stdin input using cmd.exe
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
        # Build command string using this shell's quoting rules
        command_string = join(executable, *args)

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using cmd.exe's /c flag
        Timeout.timeout(timeout) do
          execution = lambda do
            Open3.popen3(env_hash, 'cmd', '/c', command_string) do |stdin, stdout, stderr, wait_thr|
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
