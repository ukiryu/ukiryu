# frozen_string_literal: true

require_relative 'models/executable_info'

module Ukiryu
  # Executable locator for finding tool executables
  #
  # Uses OOP discovery strategies:
  # - AliasDiscovery (via Shell class)
  # - SystemCommandDiscovery (which/where/command -v)
  # - PathDiscovery (manual PATH search)
  #
  # @example Finding an executable
  #   path = ExecutableLocator.find(
  #     tool_name: 'imagemagick',
  #     aliases: ['magick']
  #   )
  module ExecutableLocator
    INTERNAL_COMMAND_TIMEOUT = 5

    class << self
      # Find an executable by name
      #
      # @param tool_name [String] the primary tool name
      # @param aliases [Array<String>] alternative names to try
      # @param platform [Symbol] the platform (defaults to Runtime.platform)
      # @return [String, nil] the executable path or nil if not found
      def find(tool_name:, aliases: [], platform: nil)
        result = find_with_info(tool_name: tool_name, aliases: aliases, platform: platform)
        result&.dig(:path)
      end

      # Find an executable with full discovery information
      #
      # @param tool_name [String] the primary tool name
      # @param aliases [Array<String>] alternative names to try
      # @param platform [Symbol] the platform (defaults to Runtime.platform)
      # @return [Hash, nil] {path: "...", info: ExecutableInfo} or nil if not found
      def find_with_info(tool_name:, aliases: [], platform: nil)
        platform ||= Ukiryu::Runtime.instance.platform
        context = DiscoveryContext.new(platform)

        # Debug logging for Windows CI
        if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (platform == :windows && ENV['CI'])
          warn "[UKIRYU DEBUG ExecutableLocator] Searching for tool: #{tool_name.inspect}"
          warn "[UKIRYU DEBUG ExecutableLocator] Aliases: #{aliases.inspect}"
          warn "[UKIRYU DEBUG ExecutableLocator] Detected shell: #{context.shell_sym.inspect}"
          warn "[UKIRYU DEBUG ExecutableLocator] Shell class: #{context.shell_class.inspect}"
        end

        # Try primary name first
        result = DiscoveryStrategy.discover(tool_name, context)
        warn "[UKIRYU DEBUG ExecutableLocator] Found #{tool_name}: #{result[:path]}" if result && (ENV['UKIRYU_DEBUG_EXECUTABLE'] || (platform == :windows && ENV['CI']))
        return result if result

        # Try aliases
        aliases.each do |alias_name|
          result = DiscoveryStrategy.discover(alias_name, context)
          warn "[UKIRYU DEBUG ExecutableLocator] Found alias #{alias_name}: #{result[:path]}" if result && (ENV['UKIRYU_DEBUG_EXECUTABLE'] || (platform == :windows && ENV['CI']))
          return result if result
        end

        warn "[UKIRYU DEBUG ExecutableLocator] NO EXECUTABLE FOUND for #{tool_name} or aliases #{aliases}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (platform == :windows && ENV['CI'])

        nil
      end

      # Find an executable in the system PATH
      #
      # @param command [String] the command or executable name
      # @param additional_paths [Array<String>] additional search paths (for backward compatibility)
      # @return [String, nil] the full path to the executable, or nil if not found
      def find_in_path(command, additional_paths: [])
        PathScanner.find(command, additional_paths: additional_paths)
      end
    end

    # Encapsulates the discovery environment details
    #
    # @api private
    class DiscoveryContext
      attr_reader :platform, :shell_sym, :shell_class

      def initialize(platform)
        @platform = platform
        @shell_sym = Shell.detect
        @shell_class = Shell.class_for(@shell_sym)
      end
    end

    # OOP Strategy for executable discovery
    #
    # Tries multiple discovery strategies in order:
    # 1. Alias discovery (via Shell class)
    # 2. System command discovery (which/where/command -v)
    # 3. Manual PATH search
    #
    # @api private
    module DiscoveryStrategy
      class << self
        # Try all discovery strategies
        #
        # @param command [String] the command to locate
        # @param context [DiscoveryContext] discovery environment
        # @return [Hash, nil] discovery result or nil
        def discover(command, context)
          warn "[UKIRYU DEBUG DiscoveryStrategy] Discovering: #{command.inspect}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])

          # Try AliasDiscovery
          result = AliasDiscovery.discover(command, context)
          if result
            warn "[UKIRYU DEBUG DiscoveryStrategy] AliasDiscovery found: #{result[:path]}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])
            return result
          end

          # Try SystemCommandDiscovery
          result = SystemCommandDiscovery.discover(command, context)
          if result
            warn "[UKIRYU DEBUG DiscoveryStrategy] SystemCommandDiscovery found: #{result[:path]}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])
            return result
          end

          # Try PathDiscovery
          result = PathDiscovery.discover(command, context)
          if result
            warn "[UKIRYU DEBUG DiscoveryStrategy] PathDiscovery found: #{result[:path]}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])
            return result
          end

          warn "[UKIRYU DEBUG DiscoveryStrategy] NO STRATEGY FOUND: #{command}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])

          nil
        end
      end
    end

    # Alias-based discovery (delegates to Shell class)
    #
    # @api private
    module AliasDiscovery
      class << self
        # Discover executable via shell alias
        #
        # @param command [String] the command to locate
        # @param context [DiscoveryContext] discovery environment
        # @return [Hash, nil] discovery result or nil
        def discover(command, context)
          warn "[UKIRYU DEBUG AliasDiscovery] Checking for alias: #{command.inspect} with shell #{context.shell_class}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])

          alias_info = context.shell_class.detect_alias(command)
          warn "[UKIRYU DEBUG AliasDiscovery] Alias info: #{alias_info.inspect}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])
          return nil unless alias_info

          alias_target = alias_info[:target]
          path = PathScanner.find(command) || PathScanner.find(alias_target)

          warn "[UKIRYU DEBUG AliasDiscovery] Alias target: #{alias_target.inspect}, path: #{path.inspect}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (context.platform == :windows && ENV['CI'])

          DiscoveryResult.build(path, :alias, context, alias_info[:definition]) if path
        end
      end
    end

    # System command discovery (which/where/command -v)
    #
    # @api private
    module SystemCommandDiscovery
      class << self
        # Discover executable via system commands
        #
        # @param command [String] the command to locate
        # @param context [DiscoveryContext] discovery environment
        # @return [Hash, nil] discovery result or nil
        def discover(command, context)
          path = SystemCommandExecutor.find(command)
          DiscoveryResult.build(path, :path, context) if path
        end
      end
    end

    # Manual PATH discovery
    #
    # @api private
    module PathDiscovery
      class << self
        # Discover executable via PATH search
        #
        # @param command [String] the command to locate
        # @param context [DiscoveryContext] discovery environment
        # @return [Hash, nil] discovery result or nil
        def discover(command, context)
          path = PathScanner.find(command)
          DiscoveryResult.build(path, :path, context) if path
        end
      end
    end

    # Build discovery results (DRY helper)
    #
    # @api private
    module DiscoveryResult
      class << self
        # Build a discovery result hash
        #
        # @param path [String] the executable path
        # @param source [Symbol] :path or :alias
        # @param context [DiscoveryContext] discovery environment
        # @param alias_definition [String, nil] optional alias definition
        # @return [Hash] {path: "...", info: ExecutableInfo}
        def build(path, source, context, alias_definition = nil)
          {
            path: path,
            info: Models::ExecutableInfo.new(
              path: path,
              source: source,
              shell: context.shell_sym,
              alias_definition: alias_definition
            )
          }
        end
      end
    end

    # Execute system commands to find executables
    #
    # @api private
    module SystemCommandExecutor
      class << self
        # Execute which/where/command -v to find executable
        #
        # @param command [String] the command to find
        # @return [String, nil] executable path or nil
        def find(command)
          platform = Runtime.instance.platform

          warn "[UKIRYU DEBUG SystemCommandExecutor] Finding command: #{command.inspect}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (platform == :windows && ENV['CI'])

          result = if platform == :windows
                     execute('where', ["#{command}.exe"])
                   else
                     execute('sh', ['-c', "command -v '#{command}' 2>/dev/null"]) ||
                       execute('which', [command])
                   end

          warn "[UKIRYU DEBUG SystemCommandExecutor] Result: #{result.inspect}" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (platform == :windows && ENV['CI'])

          result
        end

        private

        # Execute command and parse stdout
        #
        # @param executable [String] command to run
        # @param args [Array<String>] arguments
        # @return [String, nil] first line of stdout or nil
        def execute(executable, args)
          result = Executor.execute(
            executable,
            args,
            shell: Shell.detect,
            timeout: INTERNAL_COMMAND_TIMEOUT,
            allow_failure: true
          )
          return nil unless result.success?

          extract_first_line(result.stdout)
        end

        # Extract first non-empty line
        #
        # @param stdout [String] command output
        # @return [String, nil] first line or nil
        def extract_first_line(stdout)
          stdout.split("\n").first.to_s.strip.tap { |line| break nil if line.empty? }
        end
      end
    end

    # Scan PATH for executables (DRY helper)
    #
    # @api private
    module PathScanner
      class << self
        # Find executable in PATH
        #
        # @param command [String] command to find
        # @param additional_paths [Array<String>] extra paths to search
        # @return [String, nil] executable path or nil
        def find(command, additional_paths: [])
          path_extensions = PathExtensions.new

          search_paths = Platform.executable_search_paths + additional_paths
          search_paths.uniq!

          search_paths.each do |dir|
            path_extensions.each do |ext|
              exe = File.join(dir, "#{command}#{ext}")
              return exe if executable?(exe)
            end
          end

          nil
        end

        # Check if path is an executable (not a directory)
        #
        # @param path [String] path to check
        # @return [Boolean] true if executable and not directory
        def executable?(path)
          File.executable?(path) && !File.directory?(path)
        end
      end
    end

    # Handle platform-specific path extensions (.exe, .bat, etc.)
    #
    # On Windows, prioritizes .exe over .com for better PowerShell compatibility.
    # The .com extension is legacy and can cause issues with PowerShell's call
    # operator when used with I/O redirection (hangs with Open3.capture3).
    #
    # @api private
    class PathExtensions
      include Enumerable

      # Extensions to prioritize on Windows for PowerShell compatibility
      # .com files can hang PowerShell when used with I/O redirection
      PREFERRED_WINDOWS_EXTENSIONS = %w[.exe .EXE].freeze

      def initialize
        raw_extensions = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
        @extensions = prioritize_extensions(raw_extensions)
      end

      # Iterate over extensions
      #
      # @yield [String] each extension
      def each(&block)
        @extensions.each(&block)
      end

      private

      # Prioritize .exe extensions on Windows for better PowerShell compatibility
      #
      # @param extensions [Array<String>] original PATHEXT extensions
      # @return [Array<String>] reordered extensions with .exe first
      def prioritize_extensions(extensions)
        return extensions unless Platform.windows?

        # Separate preferred extensions from others
        preferred = []
        others = []

        extensions.each do |ext|
          if PREFERRED_WINDOWS_EXTENSIONS.include?(ext)
            preferred << ext
          else
            others << ext
          end
        end

        # Return preferred first, then others in original order
        preferred + others
      end
    end
  end
end
