# frozen_string_literal: true

require_relative "shell/base"

module Ukiryu
  # Shell detection and management
  #
  # Provides EXPLICIT shell detection with no fallbacks.
  # If shell cannot be determined, raises a clear error.
  module Shell
    class << self
      # Get or set the current shell (for explicit configuration)
      attr_writer :current_shell

      # Detect the current shell
      #
      # @return [Symbol] :bash, :zsh, :fish, :sh, :powershell, or :cmd
      # @raise [UnknownShellError] if shell cannot be determined
      def detect
        # Return explicitly configured shell if set
        return @current_shell if @current_shell

        # Detect based on platform and environment
        if Platform.windows?
          detect_windows_shell
        else
          detect_unix_shell
        end
      end

      # Get the shell class for the detected/configured shell
      #
      # @return [Shell::Base] the shell implementation
      def shell_class
        @shell_class ||= begin
          shell_name = detect
          class_for(shell_name)
        end
      end

      # Reset cached shell detection (mainly for testing)
      #
      # @api private
      def reset
        @current_shell = nil
        @shell_class = nil
      end

      # Get shell class by name
      #
      # @param name [Symbol] the shell name
      # @return [Class] the shell class
      # @raise [UnknownShellError] if shell class not found
      def class_for(name)
        case name
        when :bash
          require_relative "shell/bash"
          Bash
        when :zsh
          require_relative "shell/zsh"
          Zsh
        when :fish
          require_relative "shell/fish"
          Fish
        when :sh
          require_relative "shell/sh"
          Sh
        when :powershell
          require_relative "shell/powershell"
          PowerShell
        when :cmd
          require_relative "shell/cmd"
          Cmd
        else
          raise UnknownShellError, "Unknown shell: #{name}"
        end
      end

      private

      # Detect shell on Windows
      #
      # @return [Symbol] detected shell
      def detect_windows_shell
        # PowerShell check
        return :powershell if ENV["PSModulePath"]

        # Git Bash / MSYS check
        return :bash if ENV["MSYSTEM"] || ENV["MINGW_PREFIX"]

        # WSL check
        return :bash if ENV["WSL_DISTRO"]

        # Default to cmd on Windows
        :cmd
      end

      # Detect shell on Unix-like systems
      #
      # @return [Symbol] detected shell
      def detect_unix_shell
        shell_env = ENV["SHELL"]

        # Try to determine from SHELL environment variable
        if shell_env
          return :bash if shell_env.end_with?("bash")
          return :zsh if shell_env.end_with?("zsh")
          return :fish if shell_env.end_with?("fish")
          return :sh if shell_env.end_with?("sh")

          # Try to determine from executable name
          shell_name = File.basename(shell_env)
          case shell_name
          when "bash"
            :bash
          when "zsh"
            :zsh
          when "fish"
            :fish
          when "sh"
            :sh
          else
            # Unknown shell in ENV - check if executable
            if File.executable?(shell_env)
              # Return as symbol for custom shell
              shell_name.to_sym
            else
              raise UnknownShellError, unknown_shell_error_msg("Unknown shell in SHELL: #{shell_env}")
            end
          end
        else
          raise UnknownShellError, unknown_shell_error_msg("SHELL environment variable not set")
        end
      end

      # Generate error message for unknown shell
      #
      # @param reason [String] the reason for failure
      # @return [String] formatted error message
      def unknown_shell_error_msg(reason)
        <<~ERROR
          #{reason}

          Unable to detect shell automatically.

          Supported shells:
            Unix/macOS/Linux: bash, zsh, fish, sh
            Windows: powershell, cmd, bash (Git Bash/MSYS)

          Please configure explicitly:

            Ukiryu.configure do |config|
              config.default_shell = :bash  # or :zsh, :powershell, :cmd
            end

          Current environment:
            Platform: #{RbConfig::CONFIG['host_os']}
            SHELL: #{ENV['SHELL']}
            PSModulePath: #{ENV['PSModulePath']}
        ERROR
      end
    end
  end
end
