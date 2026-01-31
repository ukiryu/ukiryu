# frozen_string_literal: true

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
        platform ||= Ukiryu::Runtime.instance.platform

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

        search_paths = Ukiryu::Platform.executable_search_paths
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
      # @param search_paths [Array<String>, Models::SearchPaths, Hash] the search paths
      # @param platform [Symbol] the platform
      # @return [Array<String>] normalized array of paths
      def normalize_search_paths(search_paths, platform)
        return [] unless search_paths

        # If it's a SearchPaths model, get platform-specific paths
        return search_paths.for_platform(platform) || [] if search_paths.is_a?(Models::SearchPaths)

        # If it's a Hash, extract platform-specific paths
        if search_paths.is_a?(Hash)
          platform_paths = search_paths[platform] || search_paths[platform.to_s]
          return platform_paths || [] if platform_paths
        end

        # Already an array
        search_paths
      end

      # Try to find an executable by name
      #
      # PATH-FIRST approach: Check system PATH first, then fallback to search_paths
      #
      # @param command [String] the command name
      # @param search_paths [Array<String>] custom search paths (fallback only)
      # @return [String, nil] the executable path or nil
      def try_find(command, search_paths)
        # FIRST: Try PATH discovery using native commands (which/command -v)
        path = find_via_system_command(command)
        return path if path

        # SECOND: Check custom search paths as fallback
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

        # LAST: Manual PATH search as final fallback
        find_in_path(command)
      end

      # Find executable via system command (which/where/command -v)
      #
      # @param command [String] the command name
      # @return [String, nil] the executable path or nil
      def find_via_system_command(command)
        platform = Ukiryu::Runtime.instance.platform

        if platform == :windows
          execute_and_parse('where', ["#{command}.exe"])
        else
          # Try 'command -v' (POSIX standard) via sh first
          execute_and_parse('sh', ['-c', "command -v '#{command}' 2>/dev/null"]) ||
            # Fallback to 'which'
            execute_and_parse('which', [command])
        end
      end

      # Execute command and return parsed stdout if successful
      #
      # @param executable [String] the command to run
      # @param args [Array<String>] arguments
      # @return [String, nil] stdout stripped or nil if failed
      def execute_and_parse(executable, args)
        # Detect shell for internal utility
        shell_class = Ukiryu::Shell.detect
        result = Ukiryu::Executor.execute(executable, args, shell: shell_class, allow_failure: true)
        return nil unless result.success?

        # Take only the first line (where/which may return multiple matches)
        path = result.stdout.split("\n").first.to_s.strip
        path unless path.empty?
      end
    end
  end
end
