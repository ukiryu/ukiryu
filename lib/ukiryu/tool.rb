# frozen_string_literal: true

require_relative 'tool_cache'
require_relative 'tool_finder'

module Ukiryu
  # Tool wrapper class for external command-line tools
  #
  # Provides a Ruby interface to external CLI tools defined in YAML profiles.
  #
  # ## Usage
  #
  # ### Traditional API (backward compatible)
  #   tool = Ukiryu::Tool.get(:imagemagick)
  #   tool.execute(:convert, inputs: ["image.png"], resize: "50%")
  #
  # ### New OOP API (recommended)
  #   # Lazy autoload - creates Ukiryu::Tools::Imagemagick class on first access
  #   Ukiryu::Tools::Imagemagick.new.tap do |tool|
  #     convert_options = tool.options_for(:convert)
  #     convert_options.set(inputs: ["image.png"], resize: "50%")
  #     convert_options.output = "output.jpg"
  #     convert_options.run
  #   end
  class Tool
    include CommandBuilder

    # Include instance method modules
    require_relative 'tool/version_detection'
    include VersionDetection

    require_relative 'tool/command_resolution'
    include CommandResolution

    require_relative 'tool/executable_discovery'
    include ExecutableDiscovery

    class << self
      # Get the tools cache (bounded LRU cache)
      #
      # @return [Cache] the tools cache
      def tools_cache
        ToolCache.cache
      end

      # Get a tool by name (traditional API)
      #
      # @param name [String] the tool name
      # @param options [Hash] initialization options
      # @option options [String] :register_path path to tool profiles
      # @option options [Symbol] :platform platform to use
      # @option options [Symbol] :shell shell to use
      # @option options [String] :version specific version to use
      # @option options [Boolean] :skip_version_detection skip version-aware profile selection
      # @return [Tool] the tool instance
      def get(name, options = {})
        # Check cache first
        cache_key = cache_key_for(name, options)
        cached = tools_cache[cache_key]
        return cached if cached

        # Load profile from register
        profile = load_profile(name, options)
        raise ToolNotFoundError, "Tool not found: #{name}" unless profile

        # Create tool instance
        tool = new(profile, options)

        # Version-aware profile selection: if detected version doesn't match profile version
        # and profile has a modern_threshold, reload with appropriate version profile
        if !options[:skip_version_detection] && tool.available? && tool.executable
          detected_version = tool.version
          profile_version = profile.version
          version_detection = profile.version_detection

          # Check if we need to reload with a different profile version
          # Only proceed with version-aware reload if both versions are numeric
          if detected_version && profile_version && version_detection&.modern_threshold && profile_version.match?(/^\d/) && detected_version.match?(/^\d/)
            require 'rubygems/version'
            # Extract version number (handle "6.9.11-60 Q16 x86_64" format)
            detected_str = detected_version.split(' ')[0]
            detected = Gem::Version.create(detected_str)
            threshold = Gem::Version.new(version_detection.modern_threshold)
            Gem::Version.new(profile_version)

            # If profile version is modern (>= threshold) but detected version is legacy (< threshold)
            # or vice versa, reload with the appropriate profile
            modern = profile_is_modern?(profile_version, version_detection)
            if (modern == true && detected < threshold) ||
               (modern == false && detected >= threshold)
              # Determine appropriate version to load
              # For legacy versions, load the specific detected version (e.g., "6.9")
              # For modern versions, load the latest
              if detected >= threshold
                target_version = 'latest'
              else
                # Extract major.minor from detected version (e.g., "6.9" from "6.9.12-98")
                version_parts = detected_str.split('.')
                target_version = "#{version_parts[0]}.#{version_parts[1]}"
              end

              # Reload with correct version
              options_with_version = options.merge(version: target_version, skip_version_detection: true)
              profile = load_profile(name, options_with_version)
              raise ToolNotFoundError, "Tool not found: #{name}" unless profile

              tool = new(profile, options_with_version)

              # Update cache_key to match the new version
              cache_key = cache_key_for(name, options_with_version)
            end
          end
        end

        tools_cache[cache_key] = tool
        tool
      end

      # Find a tool by name, alias, or interface
      #
      # Searches for a tool that matches the given identifier by:
      # 1. Exact name match (fastest)
      # 2. Interface match via ToolIndex (O(1) lookup)
      # 3. Alias match via ToolIndex (O(1) lookup)
      # 4. Returns the first tool that is available on the current platform
      #
      # Debug mode: Set UKIRYU_DEBUG=1 or UKIRYU_DEBUG=true to enable structured debug output
      #
      # @param identifier [String, Symbol] the tool name, interface, or alias
      # @param options [Hash] initialization options
      # @return [Tool, nil] the tool instance or nil if not found
      def find_by(identifier, options = {})
        ToolFinder.find_by(identifier, options)
      end

      # Find all instances of a tool in PATH and aliases
      #
      # This is an explicit operation - user must ask for it.
      # Returns an array of ExecutableInfo for all matches found.
      #
      # @param tool_name [String, Symbol] the tool to find
      # @param options [Hash] initialization options
      # @return [Array<Models::ExecutableInfo>] all discovery information
      def find_all(tool_name, options = {})
        ToolFinder.find_all(tool_name, options)
      end

      # Get the tool-specific class (new OOP API)
      #
      # @param tool_name [Symbol, String] the tool name
      # @return [Class] the tool class (e.g., Ukiryu::Tools::Imagemagick)
      def get_class(tool_name)
        ToolFinder.get_class(tool_name)
      end

      # Clear the tool cache
      #
      # @api public
      def clear_cache
        ToolCache.clear
      end

      # Clear the definition cache only
      #
      # @api public
      def clear_definition_cache
        ToolCache.clear_definition_cache
      end

      # Alias for load - load from file path
      #
      # @param file_path [String] path to the YAML file
      # @param options [Hash] initialization options
      # @return [Tool] the tool instance
      def from_file(file_path, options = {})
        load(file_path, options)
      end

      # Alias for load_from_string - load from YAML string
      #
      # @param yaml_string [String] YAML content
      # @param options [Hash] initialization options
      # @return [Tool] the tool instance
      def from_definition(yaml_string, options = {})
        load_from_string(yaml_string, options)
      end

      # Configure default options
      #
      # @param options [Hash] default options
      def configure(options = {})
        @default_options ||= {}
        @default_options.merge!(options)
      end

      # Load a tool definition from a file path
      #
      # @param file_path [String] path to the YAML file
      # @param options [Hash] initialization options
      # @option options [Symbol] :validation validation mode (:strict, :lenient, :none)
      # @option options [Symbol] :version_check version check mode (:strict, :lenient, :probe)
      # @return [Tool] the tool instance
      # @raise [DefinitionLoadError] if file cannot be loaded or validation fails
      def load(file_path, options = {})
        source = Ukiryu::Definition::Sources::FileSource.new(file_path)
        profile = Ukiryu::Definition::Loader.load_from_source(source, options)
        new(profile, options.merge(definition_source: source))
      end

      # Load a tool definition from a YAML string
      #
      # @param yaml_string [String] YAML content
      # @param options [Hash] initialization options
      # @option options [String] :file_path optional file path for error messages
      # @option options [Symbol] :validation validation mode (:strict, :lenient, :none)
      # @option options [Symbol] :version_check version check mode (:strict, :lenient, :probe)
      # @return [Tool] the tool instance
      # @raise [DefinitionLoadError] if YAML cannot be parsed or validation fails
      def load_from_string(yaml_string, options = {})
        source = Ukiryu::Definition::Sources::StringSource.new(yaml_string)
        profile = Ukiryu::Definition::Loader.load_from_source(source, options)
        new(profile, options.merge(definition_source: source))
      end

      # Load a tool from bundled system locations
      #
      # Searches standard system locations for tool definitions:
      # - /usr/share/ukiryu/
      # - /usr/local/share/ukiryu/
      # - /opt/homebrew/share/ukiryu/
      # - C:\\Program Files\\Ukiryu\\
      #
      # @param tool_name [String, Symbol] the tool name
      # @param options [Hash] initialization options
      # @return [Tool, nil] the tool instance or nil if not found
      def from_bundled(tool_name, options = {})
        search_paths = bundled_definition_search_paths

        search_paths.each do |base_path|
          Dir.glob(File.join(base_path, tool_name.to_s, '*.yaml')).each do |file|
            return load(file, options)
          rescue DefinitionLoadError, DefinitionNotFoundError
            # Try next file
            next
          end
        end

        nil
      end

      # Get bundled definition search paths
      #
      # @return [Array<String>] list of search paths
      def bundled_definition_search_paths
        platform = Ukiryu::Platform.detect

        paths = case platform
                when :macos, :linux
                  [
                    '/usr/share/ukiryu',
                    '/usr/local/share/ukiryu',
                    '/opt/homebrew/share/ukiryu'
                  ]
                when :windows
                  [
                    File.expand_path('C:/Program Files/Ukiryu'),
                    File.expand_path('C:/Program Files (x86)/Ukiryu')
                  ]
                else
                  []
                end

        # Add user-local path
        paths << File.expand_path('~/.local/share/ukiryu')

        paths
      end

      # Extract tool definition from an installed CLI tool
      #
      # Attempts to extract a tool definition by:
      # 1. Trying the tool's native `--ukiryu-definition` flag
      # 2. Parsing the tool's `--help` output as a fallback
      #
      # @param tool_name [String, Symbol] the tool name to extract
      # @param options [Hash] extraction options
      # @option options [String] :output optional output file path
      # @option options [Symbol] :method specific method (:native, :help, :auto)
      # @option options [Boolean] :verbose enable verbose output
      # @return [Hash] result with :success, :yaml, :method, :error keys
      #
      # @example Extract definition from git
      #   result = Tool.extract_definition(:git)
      #   if result[:success]
      #     puts result[:yaml]
      #   end
      #
      # @example Extract and write to file
      #   result = Tool.extract_definition(:git, output: './git.yaml')
      def extract_definition(tool_name, options = {})
        result = Ukiryu::Extractors::Extractor.extract(tool_name, options)

        # Write to output file if specified
        output = options.delete(:output)
        if output && result[:success]
          require 'fileutils'
          FileUtils.mkdir_p(File.dirname(output))
          File.write(output, result[:yaml])
        end

        result
      end

      private

      # Generate a cache key for a tool
      def cache_key_for(name, options)
        ToolCache.cache_key_for(name, options)
      end

      # Load a profile for a tool
      def load_profile(name, options = {})
        Ukiryu::Tools::Generator.load_tool_definition(name.to_s, version: options[:version])
      end

      # Load a built-in profile
      def load_builtin_profile(_name, _options)
        # This will be extended with bundled profiles
        nil
      end
    end

    # Create a new Tool instance
    #
    # @param profile [Models::ToolDefinition] the tool definition model
    # @param options [Hash] initialization options
    # @option options [Definition::Source] :definition_source the source of this definition
    def initialize(profile, options = {})
      @profile = profile
      @options = options
      @definition_source = options[:definition_source]
      runtime = Ukiryu::Runtime.instance

      # Allow override via options for testing
      @platform = options[:platform]&.to_sym || runtime.platform
      @shell = options[:shell]&.to_sym || runtime.shell
      @version = options[:version]

      # Find compatible profile
      @command_profile = find_command_profile
      raise ProfileNotFoundError, "No compatible profile for #{name}" unless @command_profile

      # Find executable
      @executable = find_executable
    end

    # Get the raw profile data
    #
    # @return [Hash] the tool profile
    attr_reader :profile

    # Get the tool name
    #
    # @return [String] the tool name
    def name
      @profile.name
    end

    # Get the tool version
    #
    # @return [String, nil] the tool version
    def version
      return @version if @version

      info = detect_version
      info&.to_s
    end

    # Get the tool version info (full metadata)
    #
    # @return [Models::VersionInfo, nil] the version info or nil
    def version_info
      @version_info ||= detect_version
    end

    # Get the definition source if loaded from non-register source
    #
    # @return [Definition::Source, nil] the definition source
    attr_reader :definition_source

    # Get the definition path if loaded from file
    #
    # @return [String, nil] the file path
    def definition_path
      @definition_source&.path if @definition_source.respond_to?(:path)
    end

    # Get the definition mtime if loaded from file
    #
    # @return [Time, nil] the file modification time
    def definition_mtime
      @definition_source&.mtime if @definition_source.respond_to?(:mtime)
    end

    # Get the executable path
    #
    # @return [String] the executable path
    attr_reader :executable

    # Get the executable discovery information
    #
    # @return [Models::ExecutableInfo, nil] information about how the executable was found
    attr_reader :executable_info

    # Check if the tool is available
    #
    # @return [Boolean]
    def available?
      !@executable.nil?
    end

    # Get the reason why the tool is not available
    #
    # Returns nil if the tool is available, or a string explaining why not.
    # This helps users understand issues like:
    # - Tool not installed
    # - Wrong version installed (e.g., impostor tool)
    #
    # @return [String, nil] reason for unavailability, or nil if available
    def unavailability_reason
      return nil if available?

      # Executable not found
      "Tool '#{name}' not found in PATH. Please install the tool and ensure it's in your PATH."
    end

    # Get the commands defined in the active profile
    #
    # @return [Hash, nil] the commands hash
    def commands
      @command_profile.commands
    end

    # Get a command definition by name
    #
    # @param command_name [String, Symbol] the command name
    # @return [CommandDefinition, nil] the command definition or nil if not found
    def command_definition(command_name)
      @command_profile.command(command_name.to_s)
    end

    # Normalize params to hash
    #
    # Converts params to a hash with symbol keys, handling both hash and options objects.
    #
    # @param params [Hash, Object] the params to normalize
    # @return [Hash] normalized hash with symbol keys
    def normalize_params(params)
      if params.is_a?(Hash) && params.keys.none? { |k| k.is_a?(Symbol) }
        # Likely has string keys from CLI, convert to symbols
        params.transform_keys(&:to_sym)
      elsif !params.is_a?(Hash)
        # It's an options object, convert to hash
        Ukiryu::OptionsBuilder.to_hash(params)
      else
        params
      end
    end

    # Execute command with common configuration
    #
    # @param executable [String] the executable to run
    # @param args [Array] command arguments
    # @param command_def [Models::CommandDefinition] the command definition
    # @param params [Hash] command parameters
    # @param execution_timeout [Integer] timeout in seconds for command execution (required)
    # @param stdin [String, nil] optional stdin input
    # @return [Executor::Result] the execution result
    def execute_with_config(executable, args, command_def, params, execution_timeout:, stdin:)
      Ukiryu::Executor.execute(
        executable,
        args,
        env: build_env_vars(command_def, @command_profile, params),
        timeout: execution_timeout,
        shell: @shell,
        stdin: stdin,
        tool_name: @profile.name,
        command_name: command_def.name
      )
    end

    # Execute a command defined in the profile
    #
    # @param command_name [Symbol] the command to execute
    # @param params [Hash, Object] command parameters (hash or options object)
    # @param execution_timeout [Integer] timeout in seconds for command execution (required)
    # @return [Executor::Result] the execution result
    def execute_simple(command_name, execution_timeout:, **params)
      command = @command_profile.command(command_name.to_s)

      raise ArgumentError, "Unknown command: #{command_name}" unless command

      # Normalize params to hash with symbol keys
      params = normalize_params(params)

      # Extract stdin parameter if present (special parameter, not passed to command)
      stdin = params.delete(:stdin)

      # Build command arguments
      args = build_args(command, params)

      # Determine the executable to use
      # For tools with subcommands (v7 style for identify/mogrify), use @executable with the subcommand
      # For tools without subcommands, the behavior depends on the profile version:
      # - v7 (modern): convert has no subcommand but uses 'magick' executable
      # - v6 (legacy): each command (convert, identify, mogrify) is a standalone executable
      command_executable = if command.respond_to?(:has_subcommand?) && command.has_subcommand?
                             # v7 style: e.g., magick identify -> @executable is 'magick', subcommand is 'identify'
                             @executable
                           elsif command.respond_to?(:has_subcommand?) && !command.has_subcommand?
                             # No subcommand - need to determine if this is v7 or v6 style
                             # Check if profile has a modern_threshold and profile version is modern
                             if self.class.profile_is_modern?(@profile.version, @profile.version_detection)
                               # v7 style: convert command (no subcommand) uses 'magick' executable
                               @executable
                             else
                               # v6 style: each command is a standalone executable
                               # Check if command-specific executable exists on the filesystem
                               exe_dir = File.dirname(@executable)
                               exe_name = command.name
                               exe_path = File.join(exe_dir, exe_name)

                               # Use command-specific executable if profile explicitly allows it
                               # This is determined by checking if the command has standalone_executable: true
                               allows_standalone = if command.respond_to?(:standalone_executable)
                                                   command.standalone_executable == true
                                                 else
                                                   false
                                                 end

                               same_dir_as_exec = allows_standalone &&
                                                     File.executable?(exe_path) &&
                                                     File.dirname(exe_path) == exe_dir

                               if same_dir_as_exec
                                 exe_path
                               else
                                 @executable
                               end
                             end
                           else
                             # Fallback to @executable
                             @executable
                           end

      # Execute with environment and stdin, passing tool_name and command_name for exit code lookups
      execute_with_config(command_executable, args, command, params, execution_timeout: execution_timeout, stdin: stdin)
    end

    # Check if a command is available
    #
    # @param command_name [Symbol] the command name
    # @return [Boolean]
    def command?(command_name)
      !@command_profile.command(command_name.to_s).nil?
    end

    # Get the options class for a command
    #
    # @param command_name [Symbol] the command name
    # @return [Class] the options class for this command
    def options_for(command_name)
      Ukiryu::OptionsBuilder.for(@profile.name, command_name)
    end

    # Get the routing table from the active profile
    #
    # @return [Models::Routing, nil] the routing table or nil if not defined
    def routing
      return nil unless @command_profile.routing?

      @command_profile.routing
    end

    # Check if this tool has routing defined
    #
    # @return [Boolean] true if routing table is defined and non-empty
    def routing?
      !routing.nil? && !routing.empty?
    end

    # Check if a profile version is "modern" based on version_detection modern_threshold
    #
    # @param profile_version [String] the profile version
    # @param version_detection [Models::VersionDetection] the version detection config
    # @return [Boolean, nil] true if profile is modern (>= threshold), false if legacy, nil if can't determine
    def self.profile_is_modern?(profile_version, version_detection)
      return nil unless version_detection&.modern_threshold

      require 'rubygems/version'

      # Skip version comparison for non-numeric versions (e.g., "generic")
      return nil unless profile_version.match?(/^\d/)

      profile_ver = Gem::Version.new(profile_version)
      threshold = Gem::Version.new(version_detection.modern_threshold)

      profile_ver >= threshold
    rescue ArgumentError
      # If version parsing fails, treat as non-versioned (return nil)
      nil
    end
  end
end
