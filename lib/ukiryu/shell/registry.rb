# frozen_string_literal: true

module Ukiryu
  module Shell
    # Registry for shell implementations
    #
    # Provides a self-registration pattern for shells, making it easy to add
    # new shells without modifying the core Shell module.
    #
    # == Usage
    #
    # # Define a new shell
    # class Ukiryu::Shell::Nushell < Base
    #   PLATFORM = :unix
    #   SHELL_NAME = :nushell
    #   EXECUTABLE = 'nu'
    # end
    #
    # # Auto-registers with the registry
    # Shell::Registry.register(Nushell)
    #
    # # Now you can use it
    # Shell.class_for(:nushell)  # => Nushell
    #
    class Registry
      @registry = {}
      @mutex = Mutex.new

      class << self
        # Register a shell class
        #
        # @param shell_class [Class<Base>] the shell class to register
        # @return [true]
        #
        def register(shell_class)
          @mutex.synchronize do
            name = shell_class::SHELL_NAME
            platform = shell_class::PLATFORM

            @registry[name] = shell_class
            @registry[platform] ||= []
            @registry[platform] << shell_class unless @registry[platform].include?(shell_class)

            true
          end
        end

        # Get a shell class by name
        #
        # @param name [Symbol] the shell name
        # @return [Class<Base>] the shell class
        # @raise [UnknownShellError] if shell is not registered
        #
        def for_name(name)
          @registry[name.to_sym] || raise(Errors::UnknownShellError, "Unknown shell: #{name}")
        end

        # Get all shells for a platform
        #
        # @param platform [Symbol] the platform (:unix, :windows, :powershell)
        # @return [Array<Class<Base>>] shell classes for the platform
        #
        def for_platform(platform)
          @registry[platform] || []
        end

        # Get the default shell for a platform
        #
        # @param platform [Symbol] the platform
        # @return [Class<Base>, nil] the default shell class
        #
        def default_for_platform(platform)
          shells = for_platform(platform)
          shells.first
        end

        # Check if a shell is registered
        #
        # @param name [Symbol] the shell name
        # @return [Boolean]
        #
        def registered?(name)
          @registry.key?(name.to_sym)
        end

        # Get all registered shell names
        #
        # @return [Array<Symbol>] shell names
        #
        def shell_names
          @registry.keys.select { |k| k.is_a?(Symbol) && !%i[unix windows powershell].include?(k) }
        end

        # Get all registered platform names
        #
        # @return [Array<Symbol>] platform names
        #
        def platform_names
          @registry.keys.select { |k| %i[unix windows powershell].include?(k) }
        end

        # Get all registered shells
        #
        # @return [Array<Class<Base>>] all registered shell classes
        #
        def all_shells
          @registry.values.flatten.uniq
        end

        # Reset the registry (for testing)
        #
        def reset
          @mutex.synchronize do
            @registry = {}
          end
        end

        # Register all built-in shells
        #
        # This is called automatically when the module is loaded.
        #
        # @api private
        #
        def register_builtin_shells
          register(Bash)
          register(Zsh)
          register(Fish)
          register(Sh)
          register(Dash)
          register(Tcsh)
          register(PowerShell)
          register(Cmd)
        end
      end
    end
  end
end

# Auto-register built-in shells when loaded
require_relative 'base'
require_relative 'unix_base'
require_relative 'bash'
require_relative 'zsh'
require_relative 'fish'
require_relative 'sh'
require_relative 'dash'
require_relative 'tcsh'
require_relative 'powershell'
require_relative 'cmd'

Ukiryu::Shell::Registry.register_builtin_shells
