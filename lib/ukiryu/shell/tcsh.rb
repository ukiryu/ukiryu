# frozen_string_literal: true

require 'open3'
require 'timeout'

module Ukiryu
  module Shell
    # Tcsh (TENEX C Shell) implementation
    #
    # Tcsh is a C shell variant with enhancements including command-line editing,
    # history expansion, and programmable completion.
    #
    # Key differences from bash/sh:
    # - Uses C shell syntax (not POSIX sh compatible)
    # - History expansion with ! (major difference)
    # - Variable assignment: set var = value
    # - Environment variables: setenv VAR value
    # - Arrays: set arr = (a b c)
    # - Special characters: ! ^ ~ # $ * ? [ ] { } | ; & < > ( )
    #
    # Tcsh cannot inherit from UnixBase because it uses different syntax
    # and doesn't support the same -c flag execution method.
    class Tcsh < Base
      SHELL_NAME = :tcsh
      PLATFORM = :unix
      EXECUTABLE = 'tcsh'

      # Detect if a command is a Tcsh alias
      #
      # Tcsh uses the 'alias' builtin with its own format.
      #
      # @param command_name [String] the command to check
      # @return [Hash, nil] {definition: "...", target: "..."} or nil if not an alias
      def self.detect_alias(command_name)
        # Tcsh's alias command returns: "alias ll ls -l"
        result = `tcsh -c "alias #{command_name}" 2>/dev/null`
        return nil unless result

        # Parse tcsh alias format
        # Format: "alias ll ls -l" or "ll: aliased to ls -l"
        if result =~ /^#{command_name}\s+(.+)$/
          { definition: result.strip, target: ::Regexp.last_match(1).split(/\s+/).first }
        elsif result =~ /^#{command_name}:\s+aliased to\s+(.+)$/
          { definition: result.strip, target: ::Regexp.last_match(1).split(/\s+/).first }
        end
        nil
      end

      def name
        :tcsh
      end

      # Escape a string for Tcsh
      #
      # Tcsh has complex escaping rules:
      # - ! must always be escaped (history expansion)
      # - Other special chars: ^ ~ # $ * ? [ ] { } | ; & < > ( )
      # - Backslash escapes the next character
      #
      # @param string [String] the string to escape
      # @return [String] the escaped string
      def escape(string)
        # Escape characters that have special meaning in tcsh
        # ! is the most important (history expansion)
        # $ is used for variables
        # ` for command substitution
        # " for quoting
        # \ for escaping
        # Other special chars that might need escaping in certain contexts
        string.to_s.gsub(/[!$`"\\]/) { "\\#{::Regexp.last_match(0)}" }
      end

      # Quote an argument for Tcsh
      #
      # Tcsh supports both single and double quotes.
      # Single quotes are literal (except for ' which ends the quote).
      # Double quotes allow variable expansion and command substitution.
      #
      # However, ! (history expansion) can still occur even in quotes!
      # The safest approach is to escape ! with backslash first.
      #
      # @param string [String] the string to quote
      # @return [String] the quoted string
      def quote(string)
        # For tcsh, we need to:
        # 1. Escape ! characters (history expansion)
        # 2. Escape ' characters if present
        # 3. Wrap in single quotes
        escaped = string.to_s.gsub(/!/) { '\\!' }.gsub("'") { "'\\''" }
        "'#{escaped}'"
      end

      # Format an environment variable reference
      #
      # @param name [String] the variable name
      # @return [String] the formatted reference ($VAR)
      def env_var(name)
        "$#{name}"
      end

      # Join executable and arguments into a command line
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] the arguments
      # @return [String] the complete command line
      def join(executable, *args)
        [quote(executable), *args.map { |a| quote(a) }].join(' ')
      end

      # Format a file path for Tcsh
      # Tcsh on Unix uses forward slashes
      #
      # @param path [String] the file path
      # @return [String] the formatted path
      def format_path(path)
        path
      end

      # Tcsh doesn't need DISPLAY variable
      #
      # @return [Hash] empty hash
      def headless_environment
        {}
      end

      # Execute a command using Tcsh
      #
      # Tcsh uses -c flag for command execution, similar to other shells.
      #
      # @param executable [String] the executable path
      # @param args [Array<String>] command arguments
      # @param env [Environment] environment variables
      # @param timeout [Integer] timeout in seconds
      # @param cwd [String, nil] working directory (nil for current directory)
      # @return [Hash] execution result with :status, :stdout, :stderr keys
      # @raise [Timeout::Error] if command times out
      def execute_command(executable, args, env, timeout, cwd = nil)
        require 'open3'
        require 'timeout'

        # Build command string using this shell's quoting rules
        command_string = join(executable, *args)

        # Find tcsh executable
        tcsh_path = Ukiryu::Executor.find_executable('tcsh')
        raise 'tcsh not found in system PATH' unless tcsh_path

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using tcsh's -c flag
        Timeout.timeout(timeout) do
          execution = lambda do
            stdout, stderr, status = Open3.capture3(env_hash, tcsh_path, '-c', command_string)
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
        raise Timeout::Error, "Command timed out after #{timeout}s: #{executable}"
      end

      # Execute a command with stdin input using Tcsh
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
        require 'open3'
        require 'timeout'

        # Build command string using this shell's quoting rules
        command_string = join(executable, *args)

        # Find tcsh executable
        tcsh_path = Ukiryu::Executor.find_executable('tcsh')
        raise 'tcsh not found in system PATH' unless tcsh_path

        # Convert Environment to Hash ONLY at Open3 call site
        env_hash = environment_to_h(env)

        # Execute using tcsh's -c flag
        Timeout.timeout(timeout) do
          execution = lambda do
            Open3.popen3(env_hash, tcsh_path, '-c', command_string) do |stdin, stdout, stderr, wait_thr|
              # Write stdin data
              begin
                if stdin_data.is_a?(IO)
                  IO.copy_stream(stdin_data, stdin)
                elsif stdin_data.is_a?(String)
                  stdin.write(stdin_data)
                end
              rescue Errno::EPIPE
                # Process closed stdin early (e.g., 'head' command)
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
        raise Timeout::Error, "Command timed out after #{timeout}s: #{executable}"
      end
    end
  end
end
