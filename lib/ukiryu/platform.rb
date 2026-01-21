# frozen_string_literal: true

module Ukiryu
  # Platform detection module
  #
  # Provides explicit platform detection with clear error messages.
  # No automatic fallbacks - if platform cannot be determined, raises an error.
  module Platform
    class << self
      # Detect the current platform
      #
      # @return [Symbol] :windows, :macos, or :linux
      # @raise [UnsupportedPlatformError] if platform cannot be determined
      def detect
        if windows?
          :windows
        elsif macos?
          :macos
        elsif linux?
          :linux
        else
          # Try to determine from RbConfig
          host_os = RbConfig::CONFIG["host_os"]
          case host_os
          when /mswin|mingw|windows/i
            :windows
          when /darwin|mac os/i
            :macos
          when /linux/i
            :linux
          else
            raise UnsupportedPlatformError, <<~ERROR
              Unable to detect platform. Host OS: #{host_os}

              Supported platforms: Windows, macOS, Linux

              Please configure platform explicitly:
                Ukiryu.configure do |config|
                  config.platform = :linux # or :macos, :windows
                end
            ERROR
          end
        end
      end

      # Check if running on Windows
      #
      # @return [Boolean]
      def windows?
        Gem.win_platform? || RbConfig::CONFIG["host_os"] =~ /mswin|mingw|windows/i
      end

      # Check if running on macOS
      #
      # @return [Boolean]
      def macos?
        RbConfig::CONFIG["host_os"] =~ /darwin|mac os/i
      end

      # Check if running on Linux
      #
      # @return [Boolean]
      def linux?
        RbConfig::CONFIG["host_os"] =~ /linux/i
      end

      # Check if running on a Unix-like system (macOS or Linux)
      #
      # @return [Boolean]
      def unix?
        macos? || linux?
      end

      # Get the PATH environment variable as an array
      # Handles different PATH separators on Windows (;) vs Unix (:)
      #
      # @return [Array<String>] array of directory paths
      def executable_search_paths
        @executable_search_paths ||= begin
          path_sep = windows? ? ";" : ":"
          (ENV["PATH"] || "").split(path_sep)
        end
      end

      # Reset cached paths (primarily for testing)
      #
      # @api private
      def reset_cache
        @executable_search_paths = nil
      end
    end
  end
end
