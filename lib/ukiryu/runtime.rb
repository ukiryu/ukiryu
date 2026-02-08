# frozen_string_literal: true

require 'singleton'

module Ukiryu
  # Runtime singleton for centralized platform and shell detection.
  #
  # This class provides a single source of truth for platform and shell
  # detection across the entire application, eliminating redundant detection
  # calls and ensuring consistency.
  #
  # @example
  #   platform = Ukiryu::Runtime.instance.platform
  #   shell = Ukiryu::Runtime.instance.shell
  class Runtime
    include Singleton

    # Initialize the runtime with cached values
    def initialize
      @platform = nil
      @shell = nil
      @platform_cached = false
      @shell_cached = false
      @locked = false
    end

    # Get the current platform (cached)
    #
    # @return [Symbol] the detected platform (:macos, :linux, :windows)
    def platform
      return @platform if @platform_cached

      @platform = Ukiryu::Platform.detect
      @platform_cached = true
      @platform
    end

    # Get the current shell (cached)
    #
    # Priority:
    # 1. Explicitly set shell (via shell=)
    # 2. Config.shell (from --shell CLI option, UKIRYU_SHELL env, or programmatic config)
    # 3. Auto-detected shell
    #
    # @return [Symbol] the detected shell
    def shell
      return @shell if @shell_cached

      # Check for explicit override
      override = shell_override
      if override
        @shell = override
        @shell_cached = true
        return @shell
      end

      # Auto-detect
      @shell = Ukiryu::Shell.detect
      @shell_cached = true
      @shell
    end

    # Manually set the platform (for testing)
    #
    # @param value [Symbol] the platform to set
    def platform=(value)
      raise 'Runtime is locked' if @locked

      @platform = value&.to_sym
      @platform_cached = true
    end

    # Manually set the shell (for testing)
    #
    # @param value [Symbol] the shell to set
    def shell=(value)
      raise 'Runtime is locked' if @locked

      @shell = value&.to_sym
      @shell_cached = true
    end

    # Lock the runtime to prevent further changes
    #
    # This should be called after initial configuration is complete.
    def lock!
      @locked = true
    end

    # Reset the runtime cache (for testing)
    #
    # @api private
    def reset!
      @platform = nil
      @shell = nil
      @platform_cached = false
      @shell_cached = false
      @locked = false
    end

    # Get the platform class for the current platform
    #
    # @return [Class] the platform class
    def platform_class
      Ukiryu::Platform.class_for(platform)
    end

    # Get the shell class for the current shell
    #
    # @return [Class] the shell class
    def shell_class
      Ukiryu::Shell.class_for(shell)
    end

    # Check if running on a specific platform
    #
    # @param plat [Symbol] the platform to check
    # @return [Boolean] true if running on the specified platform
    def on_platform?(plat)
      platform == plat.to_sym
    end

    # Check if using a specific shell
    #
    # @param sh [Symbol] the shell to check
    # @return [Boolean] true if using the specified shell
    def using_shell?(sh)
      shell == sh.to_sym
    end

    # Check if running on Windows
    #
    # @return [Boolean] true if on Windows
    def windows?
      on_platform?(:windows)
    end

    # Check if running on macOS
    #
    # @return [Boolean] true if on macOS
    def macos?
      on_platform?(:macos)
    end

    # Check if running on Linux
    #
    # @return [Boolean] true if on Linux
    def linux?
      on_platform?(:linux)
    end

    # Check if using a Unix-like shell
    #
    # @return [Boolean] true if using bash, zsh, fish, or sh
    def unix_shell?
      %i[bash zsh fish sh].include?(shell)
    end

    # Check if using a Windows shell
    #
    # @return [Boolean] true if using powershell or cmd
    def windows_shell?
      %i[powershell cmd].include?(shell)
    end

    private

    # Get shell override from Config
    #
    # @return [Symbol, nil] the shell override or nil
    def shell_override
      Ukiryu::Config.shell
    end
  end
end
