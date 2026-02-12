# frozen_string_literal: true

module Ukiryu
  # Shell detection and management
  #
  # Provides EXPLICIT shell detection with no fallbacks.
  # If shell cannot be determined, raises a clear error.
  #
  # Shell types are grouped by platform compatibility:
  # - `unix` - All Unix-like shells (bash, zsh, fish, sh, dash, tcsh, ash, csh, ksh, + future shells)
  # - `windows` - cmd.exe only
  # - `powershell` - PowerShell Core on all platforms
  #
  # Individual shell names are still supported for backward compatibility
  # and are mapped to their appropriate platform group.
  module Shell
    # Use autoload for lazy loading of shell implementations
    autoload :Base, 'ukiryu/shell/base'
    autoload :UnixBase, 'ukiryu/shell/unix_base'
    autoload :Bash, 'ukiryu/shell/bash'
    autoload :Zsh, 'ukiryu/shell/zsh'
    autoload :Fish, 'ukiryu/shell/fish'
    autoload :Sh, 'ukiryu/shell/sh'
    autoload :Dash, 'ukiryu/shell/dash'
    autoload :Tcsh, 'ukiryu/shell/tcsh'
    autoload :PowerShell, 'ukiryu/shell/powershell'
    autoload :Cmd, 'ukiryu/shell/cmd'
    autoload :InstanceCache, 'ukiryu/shell/instance_cache'

    # Platform-grouped shell types (new schema v1)
    PLATFORM_GROUPS = %i[unix windows powershell].freeze

    # Individual shell types (backward compatibility)
    INDIVIDUAL_SHELLS = %i[bash zsh fish sh dash tcsh powershell cmd].freeze

    # All valid shell types (platform groups + individual shells for backward compatibility)
    VALID_SHELLS = (PLATFORM_GROUPS + INDIVIDUAL_SHELLS).freeze

    # Map individual shells to their platform groups
    SHELL_TO_PLATFORM = {
      bash: :unix,
      zsh: :unix,
      fish: :unix,
      sh: :unix,
      dash: :unix,
      tcsh: :unix,
      # ash, csh, ksh, nushell, elvish, etc. would also map to :unix
      powershell: :powershell,
      pwsh: :powershell,
      cmd: :windows
    }.freeze

    # Reverse map: platform groups to individual shells
    PLATFORM_TO_SHELLS = {
      unix: %i[bash zsh fish sh dash tcsh],
      windows: %i[cmd],
      powershell: %i[powershell pwsh]
    }.freeze

    # Shell registry for custom shells
    # @api private
    class Registry
      class << self
        def shells
          @shells ||= {}
        end

        # Register a custom shell class
        #
        # @param name [Symbol] the shell name
        # @param shell_class [Class] the shell class (must inherit from Shell::Base)
        # @raise [ArgumentError] if shell_class is not a Shell::Base subclass
        def register(name, shell_class)
          raise ArgumentError, 'Shell class must inherit from Ukiryu::Shell::Base' unless shell_class.ancestors.include?(Base)

          shells[name.to_sym] = shell_class
        end

        # Lookup a shell class by name
        #
        # @param name [Symbol] the shell name
        # @return [Class, nil] the shell class or nil if not registered
        def lookup(name)
          shells[name.to_sym]
        end

        # Get all registered shell names
        #
        # @return [Array<Symbol>] list of registered shell names
        def registered_shells
          shells.keys
        end

        # Clear all registered shells (mainly for testing)
        def clear
          @shells = nil
        end
      end
    end

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

      # Get list of all valid shells (platform groups + individual shells)
      #
      # @return [Array<Symbol>] list of valid shell symbols
      def all_valid
        VALID_SHELLS.dup
      end

      # Get shells valid for current platform (returns platform groups)
      #
      # @return [Array<Symbol>] list of valid shell groups for current platform
      def valid_for_platform
        if Platform.windows?
          %i[windows powershell unix] # Windows can run all three types
        else
          %i[unix powershell] # Unix can run Unix shells and PowerShell Core
        end
      end

      # Get the platform group for a given shell
      #
      # @param shell_sym [Symbol] the shell symbol
      # @return [Symbol] the platform group (:unix, :windows, :powershell)
      # @raise [ArgumentError] if shell is not valid
      def platform_group_for(shell_sym)
        return shell_sym if PLATFORM_GROUPS.include?(shell_sym)

        unless SHELL_TO_PLATFORM.key?(shell_sym)
          raise ArgumentError,
                "Unknown shell: #{shell_sym}. Valid shells: #{VALID_SHELLS.join(', ')}"
        end

        SHELL_TO_PLATFORM[shell_sym]
      end

      # Get shell executable path for the given shell name
      #
      # @param shell_sym [Symbol] the shell symbol
      # @return [String] the shell executable path
      # @raise [ArgumentError] if shell is not valid
      def executable_path(shell_sym)
        return nil unless valid?(shell_sym)

        case shell_sym
        when :bash
          '/bin/bash'
        when :zsh
          '/bin/zsh'
        when :fish
          '/usr/bin/fish'
        when :sh
          '/bin/sh'
        when :dash
          '/bin/dash'
        when :tcsh
          '/bin/tcsh'
        when :powershell
          'pwsh' # PowerShell Core
        when :cmd
          'cmd'
        else
          raise ArgumentError, "Unknown shell: #{shell_sym}"
        end
      end

      # Convert string to shell symbol or platform group
      #
      # @param str [String] the shell name string
      # @return [Symbol] the shell symbol or platform group
      # @raise [ArgumentError] if shell name is invalid
      def from_string(str)
        shell_sym = str.to_s.downcase.to_sym
        return shell_sym if valid?(shell_sym)

        raise ArgumentError,
              "Invalid shell: #{str}. Valid: platform groups (#{PLATFORM_GROUPS.join(', ')}) or individual shells (#{INDIVIDUAL_SHELLS.join(', ')})"
      end

      # Check if a shell is available on the system
      #
      # @param shell_sym [Symbol] the shell or platform group to check
      # @return [Boolean] true if shell/platform group is available
      def available?(shell_sym)
        # Platform groups
        return unix_shell_available? if shell_sym == :unix
        return powershell_available? if shell_sym == :powershell
        return Platform.windows? if shell_sym == :windows

        # Individual shells (backward compatibility)
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
        when :dash
          shell_available_on_unix?('dash')
        when :tcsh
          shell_available_on_unix?('tcsh')
        when :pwsh
          powershell_available?
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

        # Check for test environment override (for CI testing with specific shells)
        test_shell = ENV['UKIRYU_TEST_SHELL']
        return test_shell.to_sym if test_shell && valid?(test_shell.to_sym)

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

      # Get shell class by name or platform group
      #
      # For platform groups, returns the most appropriate shell class:
      # - :unix → Bash (most common Unix shell)
      # - :windows → Cmd
      # - :powershell → PowerShell
      #
      # @param name [Symbol] the shell name or platform group
      # @return [Class] the shell class
      # @raise [UnknownShellError] if shell class not found
      def class_for(name)
        # Check registry first (for custom shells)
        registered = Registry.lookup(name)
        return registered if registered

        # Built-in shells
        case name
        when :unix
          Bash # Most common Unix shell, all Unix shells share the same quoting rules
        when :windows
          Cmd
        when :powershell
          PowerShell
        when :bash
          Bash
        when :zsh
          Zsh
        when :fish
          Fish
        when :sh
          Sh
        when :dash
          Dash
        when :tcsh
          Tcsh
        when :pwsh
          PowerShell
        when :cmd
          Cmd
        else
          raise Ukiryu::Errors::UnknownShellError, "Unknown shell: #{name}"
        end
      end

      # Register a custom shell class
      #
      # @param name [Symbol] the shell name
      # @param shell_class [Class] the shell class (must inherit from Shell::Base)
      # @raise [ArgumentError] if shell_class is not a Shell::Base subclass
      def register(name, shell_class)
        Registry.register(name, shell_class)
      end

      private

      # Detect shell on Windows
      #
      # @return [Symbol] detected shell
      def detect_windows_shell
        # PowerShell check - PREFER PowerShell over Bash on Windows
        # This ensures proper executable discovery on Windows CI with MSYS2
        return :powershell if ENV['PSModulePath']

        # Git Bash / MSYS check - only use Bash if PowerShell is not available
        # This prevents Bash alias detection from interfering with Windows executables
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
        if shell_env
          return :bash if shell_env.end_with?('bash')
          return :zsh if shell_env.end_with?('zsh')
          return :fish if shell_env.end_with?('fish')
          return :sh if shell_env.end_with?('sh')
          return :dash if shell_env.end_with?('dash')
          return :tcsh if shell_env.end_with?('tcsh')

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
          when 'dash'
            :dash
          when 'tcsh'
            :tcsh
          else
            # Unknown shell in ENV - check if executable
            unless File.executable?(shell_env)
              raise Ukiryu::Errors::UnknownShellError,
                    unknown_shell_error_msg("Unknown shell in SHELL: #{shell_env}")
            end

            # Return as symbol for custom shell
            shell_name.to_sym
          end
        else
          # SHELL not set - try fallback methods
          detected = detect_shell_from_shells_file || detect_shell_from_path
          unless detected
            raise Ukiryu::Errors::UnknownShellError, unknown_shell_error_msg(
              'Unable to detect shell: SHELL not set and no common shells found in PATH'
            )
          end
          detected
        end
      end

      # Detect shell from /etc/shells file (fallback for minimal containers like Alpine)
      #
      # @return [Symbol, nil] detected shell or nil if not found
      def detect_shell_from_shells_file
        shells_file = '/etc/shells'
        return nil unless File.exist?(shells_file)

        # Read available shells from file, filter to supported shells
        File.readlines(shells_file).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?('#')

          return :bash if line.end_with?('bash')
          return :zsh if line.end_with?('zsh')
          return :fish if line.end_with?('fish')
          return :sh if line.end_with?('sh')
          return :dash if line.end_with?('dash')
          return :tcsh if line.end_with?('tcsh')
        end

        nil
      rescue StandardError
        # If we can't read /etc/shells, continue to next fallback
        nil
      end

      # Detect shell from common shell executables in PATH (last resort)
      #
      # @return [Symbol, nil] detected shell or nil if not found
      def detect_shell_from_path
        # Check for common shells in order of preference
        %w[bash zsh fish sh dash tcsh].each do |shell|
          return shell.to_sym if system("which #{shell} > /dev/null 2>&1")
        end

        nil
      end

      # Generate error message for unknown shell
      #
      # @param reason [String] the reason for failure
      # @return [String] formatted error message
      def unknown_shell_error_msg(reason)
        <<~ERROR
          #{reason}

          Unable to detect shell automatically.

          Supported shell types:
            Platform groups:
              - unix (all Unix-like shells: bash, zsh, fish, sh, dash, tcsh, + future shells)
              - windows (cmd.exe)
              - powershell (PowerShell Core on all platforms)

            Individual shells (backward compatibility):
              Unix/macOS/Linux: bash, zsh, fish, sh, dash, tcsh
              Windows: powershell, cmd, bash (Git Bash/MSYS)

          Please configure explicitly:

            Ukiryu.configure do |config|
              config.default_shell = :bash      # or :zsh, :unix, :powershell, :cmd, etc.
            end

          Current environment:
            Platform: #{RUBY_PLATFORM}
            SHELL: #{ENV['SHELL']}
            PSModulePath: #{ENV['PSModulePath']}
        ERROR
      end

      # Check if a Unix shell is available on the system
      #
      # @return [Boolean] true if any Unix shell is available
      def unix_shell_available?
        return false if Platform.windows?

        # Check for any Unix shell in PATH
        PLATFORM_TO_SHELLS[:unix].any? { |shell| system("which #{shell} > /dev/null 2>&1") }
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
