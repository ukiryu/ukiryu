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

      # Try loading a tool using the new ImplementationIndex architecture
      # Returns nil if the tool doesn't use the new architecture
      #
      # @param name [String, Symbol] the tool name
      # @param options [Hash] loading options
      # @return [Tool, nil] the tool instance or nil if not using new architecture
      def load_with_implementation_index(name, options = {})
        require_relative 'version_scheme_resolver'

        # Try to load ImplementationIndex
        index = Register.load_implementation_index(name, options)
        return nil unless index

        # Load Interface
        interface = Register.load_interface(index.interface, options)
        return nil unless interface

        # Detect implementation and version
        impl_spec = detect_implementation_and_version(index, name, options)
        return nil unless impl_spec

        # Load ImplementationVersion
        impl_version = Register.load_implementation_version(
          name,
          impl_spec[:implementation_name],
          impl_spec[:file],
          options
        )
        return nil unless impl_version

        # Convert to old ToolDefinition format for compatibility
        profile = convert_to_tool_definition(
          name,
          interface,
          impl_version,
          impl_spec[:implementation_name],
          impl_spec[:version], # Pass detected version
          options
        )
        return nil unless profile

        # Create tool instance
        new(profile, options)
      end

      # Detect implementation and version from ImplementationIndex
      #
      # @param index [Models::ImplementationIndex] the implementation index
      # @param tool_name [String] the tool name for executable lookup
      # @param options [Hash] options including platform and shell
      # @return [Hash, nil] hash with :implementation_name, :version, :file or nil
      def detect_implementation_and_version(index, tool_name, options = {})
        # Try each implementation in order
        index.implementations.each do |impl|
          # Run detection command
          detection = impl[:detection] || impl['detection']
          detection_result = run_detection_command(detection, tool_name, options)
          next unless detection_result

          # Extract version using pattern
          # If pattern has no capture group, detection_result is returned but we should use default version
          pattern = detection[:pattern] || detection['pattern']
          version = extract_version_from_pattern(detection_result, pattern)

          # If detection succeeded but no version was extracted, check if pattern matched
          # If pattern was just a presence check (no capture group), use nil version with default spec
          if version.nil?
            # Check if pattern matched at all (presence check)
            has_pattern = detection_result.match?(Regexp.new(pattern)) if pattern
            # If pattern didn't match, skip this implementation
            next unless has_pattern
            # Pattern matched but no version - will use default version spec below
          end

          # Resolve versionian scheme
          require_relative 'version_scheme_resolver'
          version_scheme = impl[:version_scheme] || impl['version_scheme']
          scheme = VersionSchemeResolver.resolve(version_scheme)

          # Find matching version spec
          # If version is nil (presence check only), use implementation default
          if version.nil?
            versions = impl[:versions] || impl['versions']
            # Prefer implementation-level default, then version-level default, then last version
            impl_default = impl[:default] || impl['default']
            version_spec = if impl_default
                            # Find version spec matching the implementation default
                            versions.find { |v| v[:file] == impl_default || v['file'] == impl_default } || versions.last
                           else
                            versions.find { |v| v[:default] || v['default'] } || versions.last
                          end
            return {
              implementation_name: impl[:name] || impl['name'],
              version: nil,
              file: version_spec[:file] || version_spec['file'] || impl_default
            }
          end

          # Find matching version spec for detected version
          versions = impl[:versions] || impl['versions']
          version_spec = find_matching_version_spec(versions, version, scheme)

          if version_spec
            return {
              implementation_name: impl[:name] || impl['name'],
              version: version,
              file: version_spec[:file] || version_spec['file']
            }
          end
        end

        # If no implementation matched, use the first one's default
        return nil if index.implementations.empty?

        impl = index.implementations.first
        versions = impl[:versions] || impl['versions']
        # Prefer implementation-level default, then version-level default, then last version
        impl_default = impl[:default] || impl['default']
        default_spec = if impl_default
                        # Find version spec matching the implementation default
                        versions.find { |v| v[:file] == impl_default || v['file'] == impl_default } || versions.last
                       else
                        versions.find { |v| v[:default] || v['default'] } || versions.last
                      end
        {
          implementation_name: impl[:name] || impl['name'],
          version: nil,
          file: default_spec[:file] || default_spec['file'] || impl_default
        }
      end

      # Run detection command for an implementation
      #
      # @param detection [Hash] detection configuration
      # @param tool_name [String] the tool name for executable lookup
      # @param options [Hash] options
      # @return [String, nil] command output or nil
      def run_detection_command(detection, tool_name, options = {})
        command = detection[:command] || detection['command']
        return nil unless command

        cmd = Array(command)

        # Support multiple executables for detection (e.g., 'convert' and 'magick' for ImageMagick)
        executables = detection[:executables] || detection['executables']
        if executables
          # Try each executable until one succeeds
          Array(executables).each do |executable|
            full_cmd = [executable] + cmd
            result = try_execute_command(full_cmd, options)
            return result if result
          end
          nil
        else
          # Use the executable from detection config, or fall back to tool_name
          executable = detection[:executable] || detection['executable'] || options[:executable] || tool_name.to_s
          full_cmd = [executable] + cmd
          try_execute_command(full_cmd, options)
        end
      end

      # Try executing a command and return stdout on success
      #
      # @param cmd [Array] command parts
      # @param options [Hash] options
      # @return [String, nil] stdout or stderr (if command failed but has output) or nil
      def try_execute_command(cmd, options = {})
        require_relative 'executor'
        require_relative 'shell'
        result = Executor.execute(
          cmd.first,
          cmd.drop(1),
          env: options[:env],
          shell: options[:shell] || Shell.detect,
          timeout: 5,
          allow_failure: true # Don't raise on non-zero exit for detection
        )
        # Scrub stdout/stderr to handle invalid UTF-8 byte sequences
        # If command succeeded, return stdout
        # If command failed but has stderr output, return stderr (for BusyBox detection)
        if result.success?
          result.stdout.scrub('')
        elsif !result.stderr.to_s.strip.empty?
          result.stderr.scrub('')
        end
      rescue StandardError
        nil
      end

      # Extract version from command output using pattern
      #
      # @param output [String] command output
      # @param pattern [String] regex pattern
      # @return [String, nil] extracted version or nil
      def extract_version_from_pattern(output, pattern)
        return nil unless output && pattern

        # Scrub output to handle invalid UTF-8 byte sequences
        scrubbed_output = output.scrub('')
        match = scrubbed_output.match(Regexp.new(pattern))
        return nil unless match

        # Return capture group if present, otherwise nil (presence check)
        match[1]
      end

      # Find matching version spec using versionian
      #
      # @param versions [Array<Hash>] version specs
      # @param detected_version [String] detected version
      # @param scheme [Versionian::VersionScheme] versionian scheme
      # @return [Hash, nil] matching version spec or nil
      def find_matching_version_spec(versions, detected_version, scheme)
        require 'versionian'

        versions.each do |version_spec|
          range_type = if version_spec[:equals]
  :equals
                       elsif version_spec[:before]
  :before
                       elsif version_spec[:after]
  :after
                       else
  version_spec[:between] ? :between : nil
end

          next unless range_type

          range = case range_type
                  when :equals
                    boundary = version_spec[:equals] || version_spec['equals']
                    Versionian::VersionRange.new(:equals, scheme, version: boundary)
                  when :before
                    boundary = version_spec[:before] || version_spec['before']
                    Versionian::VersionRange.new(:before, scheme, version: boundary)
                  when :after
                    boundary = version_spec[:after] || version_spec['after']
                    Versionian::VersionRange.new(:after, scheme, version: boundary)
                  when :between
                    between = version_spec[:between] || version_spec['between']
                    from = between[:from] || between['from']
                    to = between[:to] || between['to']
                    Versionian::VersionRange.new(:between, scheme, from: from, to: to)
                  end

          return version_spec if range&.matches?(detected_version)
        end
        nil
      end

      # Convert ImplementationVersion to ToolDefinition for compatibility
      #
      # @param tool_name [String] tool name
      # @param interface [Models::Interface] interface
      # @param impl_version [Models::ImplementationVersion] implementation version
      # @param implementation_name [String] implementation name
      # @param options [Hash] options
      # @return [ToolDefinition] converted tool definition
      def convert_to_tool_definition(tool_name, interface, impl_version, implementation_name, detected_version, options = {})
        require_relative 'models/tool_definition'
        require_relative 'models/platform_profile'

        # Select compatible execution profile
        profile = impl_version.compatible_profile(
          platform: options[:platform] || Platform.detect,
          shell: options[:shell] || Shell.detect
        )

        return nil unless profile

        # Build ToolDefinition from execution profile
        # Note: implements must be an array for the v2 model
        # Only append implementation name for non-default implementations
        specific_tool_name = if implementation_name && implementation_name != 'default'
                               "#{tool_name}_#{implementation_name}"
                             else
                               tool_name
                             end
        # Use detected version if available, otherwise fall back to YAML version
        version = detected_version || impl_version.version
        # Build ToolDefinition from execution profile
        # Note: implements must be an array for the v2 model
        # Only append implementation name for non-default implementations
        specific_tool_name = if implementation_name && implementation_name != 'default'
                               "#{tool_name}_#{implementation_name}"
                             else
                               tool_name
                             end
        # Use detected version if available, otherwise fall back to YAML version
        version = detected_version || impl_version.version
        tool_def = Models::ToolDefinition.new(
          name: specific_tool_name,
          version: version,
          display_name: impl_version.display_name || "#{interface.name} #{implementation_name} #{version}",
          implements: Array(interface.name), # v2: expects array
          profiles: [convert_profile_to_platform_profile(profile, interface.actions)],
          version_detection: impl_version.version_detection, # Extract from implementation
          aliases: impl_version.aliases || []
        )

        # Resolve profile inheritance after creation
        # Debug logging for Ruby 3.4+ CI
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn '[UKIRYU DEBUG] Before resolve_inheritance!'
          warn "[UKIRYU DEBUG] tool_def.profiles.size: #{tool_def.profiles.size}"
          tool_def.profiles.each do |prof|
            prof_name = prof.name if prof.respond_to?(:name)
            prof_commands = prof.commands if prof.respond_to?(:commands)
            warn "[UKIRYU DEBUG] Profile: #{prof_name}, commands: #{prof_commands&.size || 0}"
          end
        end

        tool_def.resolve_inheritance!

        # Debug logging for Ruby 3.4+ CI
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn '[UKIRYU DEBUG] After resolve_inheritance!'
          tool_def.profiles.each do |prof|
            prof_name = prof.name if prof.respond_to?(:name)
            prof_commands = prof.commands if prof.respond_to?(:commands)
            warn "[UKIRYU DEBUG] Profile: #{prof_name}, commands: #{prof_commands&.size || 0}"
          end
        end

        tool_def
      end

      # Convert ExecutionProfile to hash format for ToolDefinition
      #
      # @param profile [Models::ExecutionProfile, Hash] execution profile
      # @param actions [Array<Hash>] interface actions
      # @return [Hash] profile hash
      def convert_profile_to_hash(profile, actions)
        # Handle both Hash and ExecutionProfile objects
        if profile.is_a?(Hash)
          # Use the actions parameter (interface.actions), not profile[:actions]
          actions_hash = actions || {}
          # Convert actions hash to array format expected by ToolDefinition
          commands_array = convert_actions_to_array(actions_hash)
          {
            'name' => profile[:name] || profile['name'],
            'display_name' => profile[:display_name] || profile['display_name'],
            'platforms' => profile[:platforms] || profile['platforms'],
            'shells' => profile[:shells] || profile['shells'],
            'option_style' => profile[:option_style] || profile['option_style'],
            'executable_name' => profile[:executable_name] || profile['executable_name'],
            'commands' => commands_array
          }
        else
          actions_hash = actions || {}
          commands_array = convert_actions_to_array(actions_hash)
          {
            'name' => profile.name,
            'display_name' => profile.display_name,
            'platforms' => profile.platforms,
            'shells' => profile.shells,
            'option_style' => profile.option_style,
            'executable_name' => profile.executable_name,
            'commands' => commands_array
          }
        end
      end

      # Convert ExecutionProfile to PlatformProfile object for ToolDefinition
      #
      # @param profile [Models::ExecutionProfile, Hash] execution profile
      # @param actions [Array<Hash>] interface actions
      # @return [PlatformProfile] platform profile object
      def convert_profile_to_platform_profile(profile, actions)
        require_relative 'models/platform_profile'
        require_relative 'models/command_definition'

        # Handle both Hash and ExecutionProfile objects
        if profile.is_a?(Hash)
          profile_data = profile
          profile_commands = profile[:commands] || profile['commands'] || []
        else
          profile_data = {
            name: profile.name,
            display_name: profile.display_name,
            platforms: profile.platforms,
            shells: profile.shells,
            option_style: profile.option_style
          }
          profile_commands = profile.commands || []
        end

        # Convert interface actions to command definitions hash (by name)
        interface_commands_hash = {}
        convert_actions_to_array(actions || []).each do |cmd|
          cmd_name = cmd[:name] || cmd['name']
          interface_commands_hash[cmd_name] = cmd
        end

        # Build command definitions by merging interface and profile data
        # If profile has commands, merge them with interface actions
        # If profile has no commands, use interface actions directly
        command_definitions = if profile_commands.nil? || profile_commands.empty?
          # No profile commands - use interface actions directly
          interface_commands_hash.map do |_cmd_name, cmd_hash|
            convert_hash_to_command_definition(cmd_hash)
          end
                              else
          # Profile has commands - merge with interface actions
          profile_commands.map do |cmd_hash|
            # Command name may be specified as 'name' or 'subcommand' field
            cmd_name = cmd_hash[:name] || cmd_hash['name'] || cmd_hash[:subcommand] || cmd_hash['subcommand']
            # Merge profile command data with interface action data
            interface_cmd = interface_commands_hash[cmd_name]
            merged_cmd_hash = if interface_cmd
                                # Deep merge: profile data takes precedence
                                deep_merge_hashes(interface_cmd, cmd_hash)
                              else
                                cmd_hash
                              end
            convert_hash_to_command_definition(merged_cmd_hash)
          end
                              end

        # Create PlatformProfile
        Models::PlatformProfile.new(
          **profile_data,
          commands: command_definitions
        )
      end

      # Deep merge two hashes (second hash takes precedence)
      #
      # @param base [Hash] base hash
      # @param override [Hash] override hash (takes precedence)
      # @return [Hash] merged hash
      def deep_merge_hashes(base, override)
        base.merge(override) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge_hashes(old_val, new_val)
          elsif new_val.nil?
            old_val
          else
            new_val
          end
        end
      end

      # Convert hash to CommandDefinition object
      #
      # @param cmd_hash [Hash] command definition hash
      # @return [CommandDefinition] command definition object
      def convert_hash_to_command_definition(cmd_hash)
        require_relative 'models/command_definition'

        # Create CommandDefinition from hash
        post_options_data = cmd_hash['post_options'] || cmd_hash[:post_options]

        # Debug logging for Ruby 3.4+ CI
        if ENV['UKIRYU_DEBUG_EXECUTABLE']
          warn "[UKIRYU DEBUG build_command_definition] cmd.name: #{cmd_hash['name'] || cmd_hash[:name]}"
          warn "[UKIRYU DEBUG build_command_definition] post_options_data: #{post_options_data.inspect}"
          warn "[UKIRYU DEBUG build_command_definition] post_options_data.class: #{post_options_data.class}" if post_options_data
          if post_options_data && post_options_data.is_a?(Array)
            post_options_data.first(2).each do |opt|
              warn "[UKIRYU DEBUG build_command_definition] post_option: #{opt.inspect}"
            end
          end
        end

        Models::CommandDefinition.new(
          name: cmd_hash['name'] || cmd_hash[:name],
          description: cmd_hash['description'] || cmd_hash[:description],
          usage: cmd_hash['usage'] || cmd_hash[:usage],
          subcommand: cmd_hash['subcommand'] || cmd_hash[:subcommand],
          belongs_to: cmd_hash['belongs_to'] || cmd_hash[:belongs_to],
          cli_flag: cmd_hash['cli_flag'] || cmd_hash[:cli_flag],
          standalone_executable: cmd_hash['standalone_executable'] || cmd_hash[:standalone_executable] || false,
          aliases: cmd_hash['aliases'] || cmd_hash[:aliases] || [],
          use_env_vars: cmd_hash['use_env_vars'] || cmd_hash[:use_env_vars] || [],
          implements: cmd_hash['implements'] || cmd_hash[:implements] || [],
          options: cmd_hash['options'] || cmd_hash[:options],
          flags: cmd_hash['flags'] || cmd_hash[:flags],
          arguments: cmd_hash['arguments'] || cmd_hash[:arguments],
          post_options: post_options_data,
          env_vars: cmd_hash['env_vars'] || cmd_hash[:env_vars],
          exit_codes: cmd_hash['exit_codes'] || cmd_hash[:exit_codes]
        )
      end

      # Convert actions hash to array format
      #
      # @param actions_data [Hash, Array] actions hash with command names as keys,
      #   or array of command definitions
      # @return [Array<Hash>] array of command definitions
      def convert_actions_to_array(actions_data)
        return [] if actions_data.nil? || actions_data.empty?

        # Handle both Hash (old format) and Array (new format from Interface)
        if actions_data.is_a?(Hash)
          actions_data.map do |command_name, command_def|
            # command_def is already a hash, just add the name if not present
            command_def = command_def.to_h
            command_def['name'] ||= command_name.to_s
            command_def
          end
        else
          # Array format - convert to hash and ensure name is set
          actions_data.map do |command_def|
            command_def = command_def.to_h
            # Flatten signature if present (interface format)
            if command_def[:signature] || command_def['signature']
              signature = command_def[:signature] || command_def['signature']
              # Merge signature contents into command_def, excluding the signature key itself
              signature.each do |key, value|
                # Handle nested structure: signature[:inputs] contains inputs/options/flags
                if [:inputs, 'inputs'].include?(key)
                  # If value is a hash, merge its contents directly
                  if value.is_a?(Hash)
                    value.each do |nested_key, nested_value|
                      # Rename 'inputs' to 'arguments' for CommandDefinition compatibility
                      target_key = case nested_key.to_s
                                   when 'inputs' then 'arguments'
                                   else nested_key.to_s
                                   end
                      command_def[target_key.to_sym] = nested_value unless [:signature, 'signature'].include?(nested_key)
                    end
                  else
                    command_def[key] = value
                  end
                else
                  command_def[key] = value unless [:signature, 'signature'].include?(key)
                end
              end
              command_def.delete(:signature)
              command_def.delete('signature')
            end
            command_def
          end
        end
      end

      # Get a tool by name using the new ImplementationIndex architecture
      #
      # @param name [String] the tool name
      # @param options [Hash] initialization options
      # @option options [String] :register_path path to tool profiles
      # @option options [Symbol] :platform platform to use
      # @option options [Symbol] :shell shell to use
      # @return [Tool] the tool instance
      def get(name, options = {})
        # Check cache first
        cache_key = cache_key_for(name, options)
        cached = tools_cache[cache_key]
        return cached if cached

        # Load using ImplementationIndex architecture
        tool = load_with_implementation_index(name, options)
        raise Ukiryu::Errors::ToolNotFoundError, "Tool not found: #{name}" unless tool

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
          rescue Ukiryu::Errors::DefinitionLoadError, Ukiryu::Errors::DefinitionNotFoundError
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
      raise Ukiryu::Errors::ProfileNotFoundError, "No compatible profile for #{name}" unless @command_profile

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

      # Use profile version if available (from implementation detection)
      profile_version = @profile.version if @profile.respond_to?(:version)
      return profile_version if profile_version

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
      # Debug logging for Ruby 4.0 CI
      if ENV['UKIRYU_DEBUG_EXECUTABLE']
        warn "[UKIRYU DEBUG execute_simple] command_name: #{command_name.inspect}"
        warn "[UKIRYU DEBUG execute_simple] params (before normalize): #{params.inspect}"
        warn "[UKIRYU DEBUG execute_simple] params.class: #{params.class}"
      end

      command = @command_profile.command(command_name.to_s)

      raise ArgumentError, "Unknown command: #{command_name}" unless command

      # Normalize params to hash with symbol keys
      params = normalize_params(params)

      if ENV['UKIRYU_DEBUG_EXECUTABLE']
        warn "[UKIRYU DEBUG execute_simple] params (after normalize): #{params.inspect}"
      end

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
                               allows_standalone = if command.respond_to?(:standalone_executable?)
                                                   command.standalone_executable?
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

      # Handle date-based versions (YYYY.MM.DD format used by some tools like ping_gnu)
      # These are release dates, not semantic versions
      # Compare by converting both to comparable formats
      if profile_version.match?(/^\d{4}\.\d{2}\.\d{2}$/) && version_detection.modern_threshold.match?(/^\d{8}$/)
        # Convert YYYY.MM.DD to YYYYMMDD for direct comparison
        profile_date = profile_version.gsub('.', '')
        threshold_date = version_detection.modern_threshold
        return profile_date >= threshold_date
      end

      profile_ver = Gem::Version.new(profile_version)
      threshold = Gem::Version.new(version_detection.modern_threshold)

      profile_ver >= threshold
    rescue ArgumentError
      # If version parsing fails, treat as non-versioned (return nil)
      nil
    end
  end
end
