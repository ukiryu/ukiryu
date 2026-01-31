# frozen_string_literal: true

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

    class << self
      # Get the tools cache (bounded LRU cache)
      #
      # @return [Cache] the tools cache
      def tools_cache
        @tools_cache ||= Ukiryu::Cache.new(max_size: 50, ttl: 3600)
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
        identifier = identifier.to_s
        runtime = Ukiryu::Runtime.instance
        platform = options[:platform] || runtime.platform
        shell = options[:shell] || runtime.shell

        # Create logger instance
        logger = Ukiryu::Logger.new

        # 1. Try exact name match first (fastest path)
        begin
          tool = get(identifier, options)
          if logger.debug_enabled?
            all_tools = Ukiryu::Register.tools
            logger.debug_section_tool_resolution(
              identifier: identifier,
              platform: platform,
              shell: shell,
              all_tools: all_tools,
              selected_tool: identifier,
              executable: tool.executable
            )
          end
          return tool
        rescue ToolNotFoundError, ProfileNotFoundError
          # Continue to search by interface/alias
        end

        # 2. Use ToolIndex for O(1) interface lookup
        index = Ukiryu::ToolIndex.instance
        interface_tool_names = index.find_all_by_interface(identifier.to_sym)
        if interface_tool_names.any?
          interface_tool_names.each do |tool_name|
            tool = get(tool_name.to_s, options)
            # Return tool only if it's available (executable found)
            return tool if tool.available?
          rescue ToolNotFoundError, ProfileNotFoundError
            # Tool indexed but not available, continue to next
          end
        end

        # 3. Use ToolIndex for O(1) alias lookup
        alias_tool_name = index.find_by_alias(identifier)
        if alias_tool_name
          begin
            return get(alias_tool_name.to_s, options)
          rescue ToolNotFoundError, ProfileNotFoundError
            # Alias indexed but tool not available, continue
          end
        end

        # 4. Fallback to exhaustive search (should rarely reach here)
        all_tools = Ukiryu::Register.tools

        all_tools.each do |tool_name|
          tool_def = Tools::Generator.load_tool_definition(tool_name)
          next unless tool_def

          # Check if tool matches by interface
          # v2: implements is an array, check if interface is in the array
          # v1: implements is a string, check for equality
          implements_value = tool_def.implements
          interface_match = if implements_value.is_a?(Array)
                             implements_value.map(&:to_sym).include?(identifier.to_sym)
                           else
                             implements_value == identifier.to_s
                           end

          # Check if tool matches by alias
          alias_match = tool_def.aliases&.include?(identifier)

          next unless alias_match || interface_match

          # Check if tool is compatible with current platform/shell
          profile = tool_def.compatible_profile(platform: platform, shell: shell)
          next unless profile

          # Create tool instance
          cache_key = cache_key_for(tool_name, options)
          cached = tools_cache[cache_key]

          if cached
            if logger.debug_enabled?
              logger.debug_section_tool_resolution(
                identifier: identifier,
                platform: platform,
                shell: shell,
                all_tools: all_tools,
                selected_tool: tool_name,
                executable: cached.executable
              )
            end
            return cached
          end

          tool = new(tool_def, options.merge(platform: platform, shell: shell))
          tools_cache[cache_key] = tool

          if logger.debug_enabled?
            logger.debug_section_tool_resolution(
              identifier: identifier,
              platform: platform,
              shell: shell,
              all_tools: all_tools,
              selected_tool: tool_name,
              executable: tool.executable
            )
          end

          return tool
        end

        if logger.debug_enabled?
          logger.debug_section_tool_not_found(
            identifier: identifier,
            platform: platform,
            shell: shell,
            all_tools: all_tools
          )
        end
        nil
      end

      # Get the tool-specific class (new OOP API)
      #
      # @param tool_name [Symbol, String] the tool name
      # @return [Class] the tool class (e.g., Ukiryu::Tools::Imagemagick)
      def get_class(tool_name)
        Ukiryu::Tools::Generator.generate_and_const_set(tool_name)
      end

      # Clear the tool cache
      #
      # @api public
      def clear_cache
        tools_cache.clear
        Ukiryu::Tools::Generator.clear_cache
      end

      # Clear the definition cache only
      #
      # @api public
      def clear_definition_cache
        Ukiryu::Definition::Loader.clear_cache
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
        runtime = Ukiryu::Runtime.instance
        platform = options[:platform] || runtime.platform
        shell = options[:shell] || runtime.shell
        version = options[:version] || 'latest'
        "#{name}-#{platform}-#{shell}-#{version}"
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
      "Tool '#{name}' not found in PATH or configured search paths. Please install the tool."
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
    # @param stdin [String, nil] optional stdin input
    # @return [Executor::Result] the execution result
    def execute_with_config(executable, args, command_def, params, stdin:)
      Ukiryu::Executor.execute(
        executable,
        args,
        env: build_env_vars(command_def, @command_profile, params),
        timeout: @profile.timeout || 90,
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
    # @return [Executor::Result] the execution result
    def execute_simple(command_name, params = {})
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

                               # Use command-specific executable if it's in the tool's search_paths
                               # OR if it exists in the same directory and the profile allows it
                               # This prevents collisions with system tools while allowing v6 commands
                               platform_paths = @profile.search_paths&.for_platform(@platform) || []
                               in_search_paths = platform_paths.any? { |sp| sp.to_s.include?(exe_path) }

                               # Check if profile explicitly allows command-specific executables for this command
                               # This is determined by checking if the command has standalone_executable: true
                               # If not specified, only use command-specific executable if in search_paths
                               allows_standalone = if command.respond_to?(:standalone_executable)
                                                   command.standalone_executable == true
                                                 else
                                                   false
                                                 end

                               same_dir_as_exec = allows_standalone &&
                                                     File.executable?(exe_path) &&
                                                     File.dirname(exe_path) == exe_dir

                               if in_search_paths || same_dir_as_exec
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
      execute_with_config(command_executable, args, command, params, stdin: stdin)
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

    # Resolve a hierarchical action path
    #
    # For tools with routing (like git), resolves paths like ['remote', 'add']
    # to their executable targets and action definitions.
    #
    # @param path [Array<String, Symbol>] the action path to resolve
    # @return [Hash, nil] resolution info with :executable, :action, :path keys
    #
    # @example
    #   tool.resolve_action_path(['remote', 'add'])
    #   # => { executable: 'git-remote', action: <CommandDefinition>, path: ['remote', 'add'] }
    #
    def resolve_action_path(path)
      return nil unless routing?
      return nil if path.empty?

      # Convert to strings
      path = path.map(&:to_s)

      # Resolve first level through routing
      first_target = routing.resolve(path.first)
      return nil unless first_target

      # Find action definition
      action = if path.size > 1
                 # Multi-level: find action with belongs_to
                 find_action_with_parent(path[0], path[1])
               else
                 # Single level: find direct command
                 command_definition(path[0])
               end

      {
        executable: first_target,
        action: action,
        path: path
      }
    end

    # Find an action that belongs to a parent command
    #
    # @param parent_name [String, Symbol] the parent command name
    # @param action_name [String, Symbol] the action name
    # @return [Models::CommandDefinition, nil] the action or nil
    #
    def find_action_with_parent(parent_name, action_name)
      parent = parent_name.to_s
      action = action_name.to_s

      # Search for command with matching belongs_to
      commands&.find do |cmd|
        cmd.belongs_to == parent && cmd.name == action
      end
    end

    # Execute a routed action (for tools with routing)
    #
    # @param path [Array<String, Symbol>] the action path (e.g., ['remote', 'add'])
    # @param params [Hash] action parameters
    # @return [Executor::Result] the execution result
    #
    # @example
    #   tool.execute_action(['remote', 'add'], name: 'origin', url: 'https://...')
    #
    def execute_action(path, params = {})
      resolution = resolve_action_path(path)
      raise ArgumentError, "Cannot resolve action path: #{path.inspect}" unless resolution

      action = resolution[:action]
      raise ArgumentError, "Action not found: #{path.inspect}" unless action

      # Normalize params to hash with symbol keys
      params = normalize_params(params)

      # Extract stdin parameter
      stdin = params.delete(:stdin)

      # Build command arguments
      args = build_args(action, params)

      # Execute with the routed executable, passing tool_name and command_name for exit code lookups
      execute_with_config(resolution[:executable], args, action, params, stdin: stdin)
    end

    # Execute a command with root-path notation (for hierarchical tools)
    #
    # Root-path uses ':' to separate levels, e.g., 'remote:add' -> ['remote', 'add']
    # This provides a cleaner API for executing routed actions.
    #
    # @param root_path [String, Symbol] the action path with ':' separator (e.g., 'remote:add')
    # @param params [Hash] action parameters
    # @return [Executor::Result] the execution result
    #
    # @example Root-path notation
    #   tool.execute('remote:add', name: 'origin', url: 'https://...')
    #   tool.execute('branch:delete', branch_name: 'feature')
    #   tool.execute('stash:save', message: 'WIP')
    #
    # @example Simple command (backward compatible)
    #   tool.execute(:convert, inputs: ['image.png'], output: 'output.jpg')
    #
    def execute(root_path, params = {})
      # Check if this is a root-path (contains ':')
      if root_path.is_a?(String) && root_path.include?(':')
        path = root_path.split(':').map(&:strip)
        execute_action(path, params)
      else
        # Use simple execute for regular commands
        execute_simple(root_path, params)
      end
    end

    private

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

    # Find the best matching command profile
    #
    # Strategy:
    # 1. If multiple profiles exist, find one matching current platform/shell
    # 2. If single profile exists, use it (PATH discovery is primary)
    # 3. If no matching profile found among multiple, raise error
    def find_command_profile
      return nil unless @profile.profiles

      # Single profile: always use as fallback (PATH discovery is primary)
      return @profile.profiles.first if @profile.profiles.one?

      # Multiple profiles: find compatible one
      @profile.profiles.find do |p|
        platforms = p.platforms&.map(&:to_sym) || []
        shells = p.shells&.map(&:to_sym) || []

        # Match if profile is universal OR compatible with current platform/shell
        (platforms.empty? || platforms.include?(@platform)) &&
          (shells.empty? || shells.include?(@shell))
      end || raise(ProfileNotFoundError,
                   "No compatible profile for #{@name}. " \
                   "Current: #{@platform}/#{@shell}")
    end

    # Find the executable path using ExecutableLocator
    def find_executable
      ::Ukiryu::ExecutableLocator.find(
        tool_name: @profile.name,
        aliases: @profile.aliases || [],
        search_paths: @profile.search_paths,
        platform: @platform
      )
    end

    # Detect tool version using VersionDetector
    #
    # Supports both legacy format (command/pattern) and new methods array.
    # The methods array allows fallback hierarchy: try command first,
    # then man page, etc.
    #
    # @return [Models::VersionInfo, nil] the version info or nil if not detected
    public

    def detect_version
      vd = @profile.version_detection
      return nil unless vd

      # Check for new detection_methods array format
      if vd.respond_to?(:detection_methods) && vd.detection_methods && !vd.detection_methods.empty?
        return detect_version_with_detection_methods(vd.detection_methods)
      end

      # Legacy format: command-based detection
      return nil if vd.command.nil? || vd.command.empty?

      # If pattern is empty, skip version detection and use hardcoded version from profile
      # This is useful for tools like BusyBox applets that don't have their own --version flag
      if vd.pattern.nil? || (vd.pattern.respond_to?(:empty?) && vd.pattern.empty?)
        return Models::VersionInfo.new(
          value: @profile.version,
          method_used: :profile,
          available_methods: [:profile]
        )
      end

      # For man page detection, the executable is 'man' and command is the tool name
      # For command detection, the executable is the tool itself
      source = vd.respond_to?(:source) ? vd.source : 'command'
      if source == 'man'
        # command is ['man', 'tool_name'], so:
        # - executable = 'man'
        # - command = ['tool_name']  (just the tool name for man)
        executable = 'man'
        command_args = vd.command[1..] # Skip 'man', use rest of array
      else
        executable = @executable
        command_args = vd.command
      end

      Ukiryu::VersionDetector.detect_info(
        executable: executable,
        command: command_args,
        pattern: vd.pattern || /(\d+\.\d+)/,
        shell: @shell,
        source: source,
        timeout: @profile.timeout || 30
      )
    end

    # Detect version using detection_methods array with fallback hierarchy
    #
    # @param detection_methods [Array] array of method definitions from YAML
    # @return [Models::VersionInfo, nil] version info or nil
    def detect_version_with_detection_methods(detection_methods)
      # Convert YAML detection_methods to format expected by VersionDetector
      detector_methods = detection_methods.map do |m|
        # Handle both Hash and Lutaml::Model objects
        type = if m.respond_to?(:type)
                 m.type
               elsif m.is_a?(Hash)
                 m[:type] || m['type']
               end

        if [:man_page, 'man_page'].include?(type)
          paths = if m.respond_to?(:paths)
                    m.paths
                  elsif m.is_a?(Hash)
                    m[:paths] || m['paths']
                  else
                    {}
                  end

          {
            type: :man_page,
            paths: paths
          }
        else
          command = if m.respond_to?(:command)
                      m.command
                    elsif m.is_a?(Hash)
                      m[:command] || m['command']
                    end

          pattern = if m.respond_to?(:pattern)
                      m.pattern
                    elsif m.is_a?(Hash)
                      m[:pattern] || m['pattern']
                    end

          {
            type: :command,
            command: command || '--version',
            pattern: pattern || /(\d+\.\d+)/
          }
        end
      end

      Ukiryu::VersionDetector.detect_with_methods(
        executable: @executable,
        methods: detector_methods,
        shell: @shell,
        timeout: @profile.timeout || 30
      )
    end

    # Check version compatibility with profile requirements
    #
    # @param mode [Symbol] check mode (:strict, :lenient, :probe)
    # @return [VersionCompatibility] the compatibility result
    def check_version_compatibility(mode = :strict)
      installed = version
      requirement = profile_version_requirement

      # If no requirement, always compatible
      if !requirement || requirement.empty?
        return Ukiryu::VersionCompatibility.new(
          installed_version: installed || 'unknown',
          required_version: 'none',
          compatible: true,
          reason: nil
        )
      end

      # If installed version unknown, probe for it
      installed = detect_version&.to_s if !installed && mode == :probe

      # If still unknown, handle based on mode
      unless installed
        if mode == :strict
          return Ukiryu::VersionCompatibility.new(
            installed_version: 'unknown',
            required_version: requirement,
            compatible: false,
            reason: 'Cannot determine installed tool version'
          )
        else
          return Ukiryu::VersionCompatibility.new(
            installed_version: 'unknown',
            required_version: requirement,
            compatible: true,
            reason: 'Warning: Could not verify version compatibility'
          )
        end
      end

      # Check compatibility
      result = Ukiryu::VersionCompatibility.check(installed, requirement)

      if !result.compatible? && mode == :lenient
        # In lenient mode, return compatible but with warning
        return VersionCompatibility.new(
          installed_version: installed,
          required_version: requirement,
          compatible: true,
          reason: "Warning: #{result.reason}"
        )
      end

      result
    end

    # Probe for a feature flag
    #
    # Tests if the tool supports a specific feature by checking
    # for a command-line flag.
    #
    # @param flag [String] the feature flag to probe (e.g., '--worktree')
    # @return [Boolean] true if the feature is supported
    def probe_flag(flag)
      return false unless @executable

      result = Executor.execute(
        @executable,
        [flag, '--help'],
        shell: @shell,
        timeout: 5
      )

      # Some tools exit 0 even for unknown flags, check stderr
      # If the flag is valid, --help should show info about it
      result.success? && !result.stderr.include?('unknown')
    end

    # Get version requirement from compatible profile
    #
    # @return [String, nil] the version requirement
    def profile_version_requirement
      @command_profile&.version_requirement
    end
  end
end
