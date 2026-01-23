# frozen_string_literal: true

require_relative 'shell/base'

module Ukiryu
  # Shell detection and management
  #
  # Provides EXPLICIT shell detection with no fallbacks.
  # If shell cannot be determined, raises a clear error.
  module Shell
    # All supported shell types
    VALID_SHELLS = %i[bash zsh fish sh powershell cmd].freeze

    # Platform-specific shell mappings
    UNIX_SHELLS = %i[bash zsh fish sh].freeze
    WINDOWS_SHELLS = %i[powershell cmd bash].freeze

    class << self
      # Get or set the current shell (for explicit configuration)
      attr_writer :current_shell

      # Check if a shell symbol is valid
      #
      # @param shell_sym [Symbol] the shell symbol to check
      # @return [Boolean] true if shell is valid
      def valid?(shell_sym)
        VALID_SHELLS.include?(shell_sym&.to_sym)
      end

      # Get list of all valid shells
      #
      # @return [Array<Symbol>] list of valid shell symbols
      def all_valid
        VALID_SHELLS.dup
      end

      # Get shells valid for current platform
      #
      # @return [Array<Symbol>] list of valid shells for current platform
      def valid_for_platform
        Platform.windows? ? WINDOWS_SHELLS.dup : UNIX_SHELLS.dup
      end

      # Convert string to shell symbol
      #
      # @param str [String] the shell name string
      # @return [Symbol] the shell symbol
      # @raise [ArgumentError] if shell name is invalid
      def from_string(str)
        shell_sym = str.to_s.downcase.to_sym
        return shell_sym if valid?(shell_sym)

        raise ArgumentError,
              "Invalid shell: #{str}. Valid shells: #{VALID_SHELLS.join(', ')}"
      end

      # Check if a shell is available on the system
      #
      # @param shell_sym [Symbol] the shell to check
      # @return [Boolean] true if shell is available
      def available?(shell_sym)
        return false unless valid?(shell_sym)

        case shell_sym
        when :bash
          shell_available_on_unix?('bash') || bash_available_on_windows?
        when :zsh
          shell_available_on_unix?('zsh')
        when :fish
          shell_available_on_unix?('fish')
        when :sh
          shell_available_on_unix?('sh')
        when :powershell
          powershell_available?
        when :cmd
          true # cmd is always available on Windows
        else
          false
        end
      end

      # Get all shells available on the current system
      #
      # @return [Array<Symbol>] list of available shells
      def available_shells
        VALID_SHELLS.select { |shell| available?(shell) }
      end

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
          require_relative 'shell/bash'
          Bash
        when :zsh
          require_relative 'shell/zsh'
          Zsh
        when :fish
          require_relative 'shell/fish'
          Fish
        when :sh
          require_relative 'shell/sh'
          Sh
        when :powershell
          require_relative 'shell/powershell'
          PowerShell
        when :cmd
          require_relative 'shell/cmd'
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
        return :powershell if ENV['PSModulePath']

        # Git Bash / MSYS check
        return :bash if ENV['MSYSTEM'] || ENV['MINGW_PREFIX']

        # WSL check
        return :bash if ENV['WSL_DISTRO']

        # Default to cmd on Windows
        :cmd
      end

      # Detect shell on Unix-like systems
      #
      # @return [Symbol] detected shell
      def detect_unix_shell
        shell_env = ENV['SHELL']

        # Try to determine from SHELL environment variable
        raise UnknownShellError, unknown_shell_error_msg('SHELL environment variable not set') unless shell_env
        return :bash if shell_env.end_with?('bash')
        return :zsh if shell_env.end_with?('zsh')
        return :fish if shell_env.end_with?('fish')
        return :sh if shell_env.end_with?('sh')

        # Try to determine from executable name
        shell_name = File.basename(shell_env)
        case shell_name
        when 'bash'
          :bash
        when 'zsh'
          :zsh
        when 'fish'
          :fish
        when 'sh'
          :sh
        else
          # Unknown shell in ENV - check if executable
          unless File.executable?(shell_env)
            raise UnknownShellError,
                  unknown_shell_error_msg("Unknown shell in SHELL: #{shell_env}")
          end

          # Return as symbol for custom shell
          shell_name.to_sym

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
            Platform: #{RUBY_PLATFORM}
            SHELL: #{ENV['SHELL']}
            PSModulePath: #{ENV['PSModulePath']}
        ERROR
      end

      # Check if a Unix shell is available on the system
      #
      # @param shell_name [String] the shell executable name
      # @return [Boolean] true if shell is available
      def shell_available_on_unix?(shell_name)
        return false if Platform.windows?

        # Check if shell is in PATH
        system("which #{shell_name} > /dev/null 2>&1")
      end

      # Check if bash is available on Windows (Git Bash/MSYS)
      #
      # @return [Boolean] true if bash is available
      def bash_available_on_windows?
        return false unless Platform.windows?

        # Check for Git Bash / MSYS
        !!(ENV['MSYSTEM'] || ENV['MINGW_PREFIX'] || ENV['WSL_DISTRO'] ||
           system('where bash >nul 2>&1'))
      end

      # Check if PowerShell is available
      #
      # @return [Boolean] true if PowerShell is available
      def powershell_available?
        return true if Platform.windows? && ENV['PSModulePath']

        # On Unix, check for PowerShell Core (pwsh)
        return true if !Platform.windows? && system('which pwsh > /dev/null 2>&1')

        false
      end
    end
  end
end
