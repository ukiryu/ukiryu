# frozen_string_literal: true

require_relative 'executor'
require_relative 'platform'

module Ukiryu
  # Executable locator for finding tool executables
  #
  # This module provides centralized executable location logic with:
  # - Custom search paths from tool profiles
  # - Shell-specific path extensions (Windows PATHEXT)
  # - Fallback to system PATH
  # - Proper OOP design (no duplicated code)
  #
  # @example Finding an executable
  #   path = ExecutableLocator.find(
  #     tool_name: 'imagemagick',
  #     aliases: ['magick'],
  #     search_paths: ['/opt/homebrew/bin/magick'],
  #     platform: :macos
  #   )
  module ExecutableLocator
    class << self
      # Find an executable by name with search paths
      #
      # @param tool_name [String] the primary tool name
      # @param aliases [Array<String>] alternative names to try
      # @param search_paths [Array<String>, Models::SearchPaths] custom search paths or SearchPaths model
      # @param platform [Symbol] the platform (defaults to Runtime.platform)
      # @return [String, nil] the executable path or nil if not found
      def find(tool_name:, aliases: [], search_paths: [], platform: nil)
        platform ||= Runtime.instance.platform

        # Convert SearchPaths model to array if needed
        paths = normalize_search_paths(search_paths, platform)

        # Try primary name first
        exe = try_find(tool_name, paths)
        return exe if exe

        # Try aliases
        aliases.each do |alias_name|
          exe = try_find(alias_name, paths)
          return exe if exe
        end

        nil
      end

      # Find an executable in the system PATH
      #
      # @param command [String] the command or executable name
      # @param additional_paths [Array<String>] additional search paths
      # @return [String, nil] the full path to the executable, or nil if not found
      def find_in_path(command, additional_paths: [])
        # Try with PATHEXT extensions (Windows executables)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']

        search_paths = Platform.executable_search_paths
        search_paths.concat(additional_paths) if additional_paths
        search_paths.uniq!

        search_paths.each do |dir|
          exts.each do |ext|
            exe = File.join(dir, "#{command}#{ext}")
            return exe if File.executable?(exe) && !File.directory?(exe)
          end
        end

        nil
      end

      private

      # Normalize search paths to array format
      #
      # @param search_paths [Array<String>, Models::SearchPaths] the search paths
      # @param platform [Symbol] the platform
      # @return [Array<String>] normalized array of paths
      def normalize_search_paths(search_paths, platform)
        return [] unless search_paths

        # If it's a SearchPaths model, get platform-specific paths
        return search_paths.for_platform(platform) || [] if search_paths.is_a?(Models::SearchPaths)

        # Already an array
        search_paths
      end

      # Try to find an executable by name
      #
      # @param command [String] the command name
      # @param search_paths [Array<String>] custom search paths
      # @return [String, nil] the executable path or nil
      def try_find(command, search_paths)
        # Check custom search paths first (both absolute paths and glob patterns)
        search_paths.each do |path_pattern|
          # Handle glob patterns
          if path_pattern.include?('*')
            Dir.glob(path_pattern).each do |expanded|
              return expanded if File.executable?(expanded) && !File.directory?(expanded)
            end
          # Handle absolute paths
          elsif File.executable?(path_pattern) && !File.directory?(path_pattern)
            return path_pattern
          end
        end

        # Fall back to PATH
        find_in_path(command)
      end
    end
  end
end
