# frozen_string_literal: true

require_relative 'registry'
require_relative 'executor'
require_relative 'shell'
require_relative 'runtime'
require_relative 'command_builder'
require_relative 'tools/base'
require_relative 'tools/generator'
require_relative 'cache'
require_relative 'executable_locator'
require_relative 'version_detector'
require_relative 'logger'
require_relative 'tool_index'
require_relative 'models/routing'

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
        @tools_cache ||= Cache.new(max_size: 50, ttl: 3600)
      end

      # Get a tool by name (traditional API)
      #
      # @param name [String] the tool name
      # @param options [Hash] initialization options
      # @option options [String] :registry_path path to tool profiles
      # @option options [Symbol] :platform platform to use
      # @option options [Symbol] :shell shell to use
      # @option options [String] :version specific version to use
      # @return [Tool] the tool instance
      def get(name, options = {})
        # Check cache first
        cache_key = cache_key_for(name, options)
        cached = tools_cache[cache_key]
        return cached if cached

        # Load profile from registry
        profile = load_profile(name, options)
        raise ToolNotFoundError, "Tool not found: #{name}" unless profile

        # Create tool instance
        tool = new(profile, options)
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
        runtime = Runtime.instance
        platform = options[:platform] || runtime.platform
        shell = options[:shell] || runtime.shell

        # Create logger instance
        logger = Logger.new

        # 1. Try exact name match first (fastest path)
        begin
          tool = get(identifier, options)
          if logger.debug_enabled?
            require_relative 'registry'
            all_tools = Registry.tools
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
        rescue ToolNotFoundError
          # Continue to search by interface/alias
        end

        # 2. Use ToolIndex for O(1) interface lookup
        index = ToolIndex.instance
        interface_metadata = index.find_by_interface(identifier.to_sym)
        if interface_metadata
          tool_name = interface_metadata.name
          begin
            return get(tool_name, options)
          rescue ToolNotFoundError
            # Tool indexed but not available, continue
          end
        end

        # 3. Use ToolIndex for O(1) alias lookup
        alias_tool_name = index.find_by_alias(identifier)
        if alias_tool_name
          begin
            return get(alias_tool_name.to_s, options)
          rescue ToolNotFoundError
            # Alias indexed but tool not available, continue
          end
        end

        # 4. Fallback to exhaustive search (should rarely reach here)
        require_relative 'registry'
        all_tools = Registry.tools

        all_tools.each do |tool_name|
          tool_def = Tools::Generator.load_tool_definition(tool_name)
          next unless tool_def

          # Check if tool matches by interface
          interface_match = tool_def.implements == identifier.to_sym

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
        Tools::Generator.generate_and_const_set(tool_name)
      end

      # Clear the tool cache
      #
      # @api public
      def clear_cache
        tools_cache.clear
        Tools::Generator.clear_cache
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
      # @raise [LoadError] if file cannot be loaded or validation fails
      def load(file_path, options = {})
        require 'yaml'
        require_relative 'models/tool_definition'

        raise LoadError, "File not found: #{file_path}" unless File.exist?(file_path)

        content = File.read(file_path)
        load_from_string(content, options.merge(file_path: file_path))
      end

      # Load a tool definition from a YAML string
      #
      # @param yaml_string [String] YAML content
      # @param options [Hash] initialization options
      # @option options [String] :file_path optional file path for error messages
      # @option options [Symbol] :validation validation mode (:strict, :lenient, :none)
      # @option options [Symbol] :version_check version check mode (:strict, :lenient, :probe)
      # @return [Tool] the tool instance
      # @raise [LoadError] if YAML cannot be parsed or validation fails
      def load_from_string(yaml_string, options = {})
        require_relative 'models/tool_definition'

        begin
          # Use lutaml-model's from_yaml to parse
          profile = Models::ToolDefinition.from_yaml(yaml_string)
        rescue Psych::SyntaxError => e
          raise LoadError, "Invalid YAML: #{e.message}"
        rescue StandardError => e
          raise LoadError, "Invalid YAML: #{e.message}"
        end

        # Validate profile if validation mode is set
        validation_mode = options[:validation] || :strict
        validate_profile(profile, validation_mode) if validation_mode != :none

        # Create tool instance
        new(profile, options)
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
            begin
              return load(file, options)
            rescue LoadError, NameError
              # Try next file
              next
            end
          end
        end

        nil
      end

      # Get bundled definition search paths
      #
      # @return [Array<String>] list of search paths
      def bundled_definition_search_paths
        require_relative 'platform'

        platform = Platform.detect

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
        require_relative 'extractors/extractor'

        result = Extractors::Extractor.extract(tool_name, options)

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

      # Validate a tool profile
      #
      # @param profile [Models::ToolDefinition] the profile to validate
      # @param mode [Symbol] validation mode (:strict, :lenient)
      # @raise [LoadError] if validation fails in strict mode
      def validate_profile(profile, mode)
        errors = []

        # Check required fields
        errors << "Missing 'name' field" unless profile.name
        errors << "Missing 'version' field" unless profile.version
        errors << "Missing 'profiles' field or profiles is empty" unless profile.profiles&.any?

        # Check ukiryu_schema format if present
        if profile.ukiryu_schema && !profile.ukiryu_schema.match?(/^\d+\.\d+$/)
          errors << "Invalid ukiryu_schema format: #{profile.ukiryu_schema}"
        end

        # Check $self URI format if present
        if profile.self_uri && !valid_uri?(profile.self_uri)
          errors << "Invalid $self URI format: #{profile.self_uri}" if mode == :strict
        end

        if errors.any?
          message = "Profile validation failed:\n  - #{errors.join("\n  - ")}"
          if mode == :strict
            raise LoadError, message
          else
            warn "[Ukiryu] #{message}" if mode == :lenient
          end
        end
      end

      # Check if a string is a valid URI
      #
      # @param uri_string [String] the URI to check
      # @return [Boolean] true if valid URI
      def valid_uri?(uri_string)
        (uri_string =~ %r{^https?://} || uri_string =~ %r{^file://}) ? true : false
      end

      # Generate a cache key for a tool
      def cache_key_for(name, options)
        runtime = Runtime.instance
        platform = options[:platform] || runtime.platform
        shell = options[:shell] || runtime.shell
        version = options[:version] || 'latest'
        "#{name}-#{platform}-#{shell}-#{version}"
      end

      # Load a profile for a tool
      def load_profile(name, _options)
        require_relative 'tools/generator'
        Tools::Generator.load_tool_definition(name.to_s)
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
    def initialize(profile, options = {})
      @profile = profile
      @options = options
      runtime = Runtime.instance

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
      @version || detect_version
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

    # Execute a command defined in the profile
    #
    # @param command_name [Symbol] the command to execute
    # @param params [Hash, Object] command parameters (hash or options object)
    # @return [Executor::Result] the execution result
    def execute_simple(command_name, params = {})
      command = @command_profile.command(command_name.to_s)

      raise ArgumentError, "Unknown command: #{command_name}" unless command

      # Convert options object to hash if needed
      if params.is_a?(Hash) && params.keys.none? { |k| k.is_a?(Symbol) }
        # Likely has string keys from CLI, convert to symbols
        params = params.transform_keys(&:to_sym)
      elsif !params.is_a?(Hash)
        # It's an options object, convert to hash
        require_relative 'options_builder'
        params = Ukiryu::OptionsBuilder.to_hash(params)
      end

      # Extract stdin parameter if present (special parameter, not passed to command)
      stdin = params.delete(:stdin)

      # Build command arguments
      args = build_args(command, params)

      # Execute with environment and stdin, passing tool_name and command_name for exit code lookups
      Executor.execute(
        @executable,
        args,
        env: build_env_vars(command, params),
        timeout: @profile.timeout || 90,
        shell: @shell,
        stdin: stdin,
        tool_name: @profile.name,
        command_name: command.name
      )
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
      require_relative 'options_builder'
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

      # Convert params to hash if needed
      params = params.transform_keys(&:to_sym) if params.is_a?(Hash)
      unless params.is_a?(Hash)
        require_relative 'options_builder'
        params = Ukiryu::OptionsBuilder.to_hash(params)
      end

      # Extract stdin parameter
      stdin = params.delete(:stdin)

      # Build command arguments
      args = build_args(action, params)

      # Execute with the routed executable, passing tool_name and command_name for exit code lookups
      Executor.execute(
        resolution[:executable],
        args,
        env: build_env_vars(action, params),
        timeout: @profile.timeout || 90,
        shell: @shell,
        stdin: stdin,
        tool_name: @profile.name,
        command_name: action.name
      )
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

    # Find the best matching command profile
    def find_command_profile
      return nil unless @profile.profiles
      return @profile.profiles.first if @profile.profiles.one?

      @profile.profiles.find do |p|
        platforms = p.platforms&.map(&:to_sym) || []
        shells = p.shells&.map(&:to_sym) || []

        # Convert array elements to symbols for comparison
        # (YAML arrays contain strings, but platform/shell are symbols)
        platform_match = platforms.empty? || platforms.include?(@platform)
        shell_match = shells.empty? || shells.include?(@shell)

        platform_match && shell_match
      end
    end

    # Find the executable path using ExecutableLocator
    def find_executable
      ExecutableLocator.find(
        tool_name: @profile.name,
        aliases: @profile.aliases || [],
        search_paths: @profile.search_paths,
        platform: @platform
      )
    end

    # Detect tool version using VersionDetector
    def detect_version
      vd = @profile.version_detection
      return nil unless vd

      VersionDetector.detect(
        executable: @executable,
        command: vd.command || '--version',
        pattern: vd.pattern || /(\d+\.\d+)/,
        shell: @shell
      )
    end

    # Check version compatibility with profile requirements
    #
    # @param mode [Symbol] check mode (:strict, :lenient, :probe)
    # @return [VersionCompatibility] the compatibility result
    def check_version_compatibility(mode = :strict)
      require_relative 'models/version_compatibility'

      installed = version
      requirement = profile_version_requirement

      # If no requirement, always compatible
      return VersionCompatibility.new(
        installed_version: installed || 'unknown',
        required_version: 'none',
        compatible: true,
        reason: nil
      ) if !requirement || requirement.empty?

      # If installed version unknown, probe for it
      if !installed && mode == :probe
        installed = detect_version
      end

      # If still unknown, handle based on mode
      if !installed
        if mode == :strict
          return VersionCompatibility.new(
            installed_version: 'unknown',
            required_version: requirement,
            compatible: false,
            reason: 'Cannot determine installed tool version'
          )
        else
          return VersionCompatibility.new(
            installed_version: 'unknown',
            required_version: requirement,
            compatible: true,
            reason: 'Warning: Could not verify version compatibility'
          )
        end
      end

      # Check compatibility
      result = VersionCompatibility.check(installed, requirement)

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

    private

    # Get version requirement from compatible profile
    #
    # @return [String, nil] the version requirement
    def profile_version_requirement
      @command_profile&.version_requirement
    end
  end
end
