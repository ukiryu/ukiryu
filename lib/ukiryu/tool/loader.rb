# frozen_string_literal: true

module Ukiryu
  class Tool
    # Handles loading of tools using the ImplementationIndex architecture
    #
    # This module extracts the complex loading pipeline from the main Tool class:
    # 1. Load ImplementationIndex from register
    # 2. Load Interface definition
    # 3. Detect implementation and version
    # 4. Load ImplementationVersion
    # 5. Convert to ToolDefinition for compatibility
    #
    # @api private
    module Loader
      class << self
        # Load a tool using the new ImplementationIndex architecture
        #
        # @param name [String, Symbol] the tool name
        # @param options [Hash] loading options
        # @return [Tool, nil] the tool instance or nil if not using new architecture
        def load_with_implementation_index(name, options = {})
          require_relative '../version_scheme_resolver'

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
          tool_definition = convert_to_tool_definition(
            name,
            interface,
            impl_version,
            impl_spec[:implementation_name],
            impl_spec[:version], # Pass detected version
            options
          )
          return nil unless tool_definition

          # Create tool instance
          Tool.new(tool_definition, options)
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
            result = try_implementation(impl, tool_name, options)
            return result if result
          end

          # If no implementation matched, use the first one's default
          fallback_to_default(index)
        end

        private

        # Try to detect version from a single implementation
        #
        # @param impl [Hash] implementation definition
        # @param tool_name [String] the tool name
        # @param options [Hash] options
        # @return [Hash, nil] implementation spec or nil
        def try_implementation(impl, tool_name, options)
          detection = impl[:detection] || impl['detection']
          detection_result = run_detection_command(detection, tool_name, options)
          return nil unless detection_result

          # Extract version using pattern
          pattern = detection[:pattern] || detection['pattern']
          version = extract_version_from_pattern(detection_result, pattern)

          # If detection succeeded but no version was extracted, check if pattern matched
          if version.nil? && pattern
            has_pattern = detection_result.match?(Regexp.new(pattern))
            return nil unless has_pattern
          end

          # Resolve version scheme and find matching spec
          build_implementation_spec(impl, version)
        end

        # Build implementation spec from detected version
        #
        # @param impl [Hash] implementation definition
        # @param version [String, nil] detected version
        # @return [Hash, nil] implementation spec or nil
        def build_implementation_spec(impl, version)
          require_relative '../version_scheme_resolver'
          version_scheme = impl[:version_scheme] || impl['version_scheme']
          scheme = VersionSchemeResolver.resolve(version_scheme)
          versions = impl[:versions] || impl['versions']

          if version.nil?
            # Use default version spec
            build_default_spec(impl, versions)
          else
            # Find matching version spec for detected version
            version_spec = find_matching_version_spec(versions, version, scheme)
            if version_spec
              {
                implementation_name: impl[:name] || impl['name'],
                version: version,
                file: version_spec[:file] || version_spec['file']
              }
            end
          end
        end

        # Build default spec when no version detected
        #
        # @param impl [Hash] implementation definition
        # @param versions [Array] version specs
        # @return [Hash] default implementation spec
        def build_default_spec(impl, versions)
          impl_default = impl[:default] || impl['default']
          version_spec = if impl_default
                           versions.find { |v| v[:file] == impl_default || v['file'] == impl_default } || versions.last
                         else
                           versions.find { |v| v[:default] || v['default'] } || versions.last
                         end
          {
            implementation_name: impl[:name] || impl['name'],
            version: nil,
            file: version_spec[:file] || version_spec['file'] || impl_default
          }
        end

        # Fallback to first implementation's default
        #
        # @param index [Models::ImplementationIndex] the implementation index
        # @return [Hash, nil] fallback spec or nil
        def fallback_to_default(index)
          return nil if index.implementations.empty?

          impl = index.implementations.first
          versions = impl[:versions] || impl['versions']
          build_default_spec(impl, versions)
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

          # Support multiple executables for detection
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
          require_relative '../executor'
          require_relative '../shell'
          result = Executor.execute(
            cmd.first,
            cmd.drop(1),
            env: options[:env],
            shell: options[:shell] || Shell.detect,
            timeout: 5,
            allow_failure: true
          )
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

          scrubbed_output = output.scrub('')
          match = scrubbed_output.match(Regexp.new(pattern))
          return nil unless match

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
            range_type = determine_range_type(version_spec)
            next unless range_type

            range = build_version_range(version_spec, range_type, scheme)
            return version_spec if range&.matches?(detected_version)
          end
          nil
        end

        # Determine the range type from a version spec
        #
        # @param version_spec [Hash] version specification
        # @return [Symbol, nil] range type (:equals, :before, :after, :between) or nil
        def determine_range_type(version_spec)
          if version_spec[:equals] || version_spec['equals']
            :equals
          elsif version_spec[:before] || version_spec['before']
            :before
          elsif version_spec[:after] || version_spec['after']
            :after
          elsif version_spec[:between] || version_spec['between']
            :between
          end
        end

        # Build a VersionRange from a version spec
        #
        # @param version_spec [Hash] version specification
        # @param range_type [Symbol] range type
        # @param scheme [Versionian::VersionScheme] version scheme
        # @return [Versionian::VersionRange, nil] version range or nil
        def build_version_range(version_spec, range_type, scheme)
          case range_type
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
        end

        # Convert ImplementationVersion to ToolDefinition for compatibility
        #
        # @param tool_name [String] tool name
        # @param interface [Models::Interface] interface
        # @param impl_version [Models::ImplementationVersion] implementation version
        # @param implementation_name [String] implementation name
        # @param detected_version [String, nil] detected version
        # @param options [Hash] options
        # @return [ToolDefinition] converted tool definition
        def convert_to_tool_definition(tool_name, interface, impl_version, implementation_name, detected_version,
                                       options = {})
          require_relative '../models/tool_definition'
          require_relative '../models/platform_profile'

          # Select compatible execution profile
          profile = impl_version.compatible_profile(
            platform: options[:platform] || Platform.detect,
            shell: options[:shell] || Shell.detect
          )

          return nil unless profile

          # Debug output for profile selection
          Logger.debug("Selected profile name: #{profile[:name] || profile['name']}",
                       category: :executable)
          Logger.debug("Profile inherits: #{profile[:inherits] || profile['inherits']}",
                       category: :executable)
          Logger.debug("Profile executable_name: #{profile[:executable_name] || profile['executable_name']}",
                       category: :executable)
          Logger.debug("Profile has commands: #{(profile[:commands] || profile['commands']).inspect[0..100]}",
                       category: :executable)
          Logger.debug("Full profile keys: #{profile.keys.inspect}", category: :executable)

          # Build tool name (append implementation name for non-default)
          specific_tool_name = build_tool_name(tool_name, implementation_name)
          version = detected_version || impl_version.version

          tool_def = Models::ToolDefinition.new(
            name: specific_tool_name,
            version: version,
            display_name: impl_version.display_name || "#{interface.name} #{implementation_name} #{version}",
            implements: Array(interface.name),
            profiles: [convert_profile_to_platform_profile(profile, interface.actions)],
            version_detection: impl_version.version_detection,
            aliases: impl_version.aliases || []
          )

          tool_def.resolve_inheritance!
          tool_def
        end

        # Build specific tool name with implementation suffix
        #
        # @param tool_name [String] base tool name
        # @param implementation_name [String] implementation name
        # @return [String] specific tool name
        def build_tool_name(tool_name, implementation_name)
          if implementation_name && implementation_name != 'default'
            "#{tool_name}_#{implementation_name}"
          else
            tool_name
          end
        end

        # Convert ExecutionProfile to PlatformProfile object
        #
        # @param profile [Models::ExecutionProfile, Hash] execution profile
        # @param actions [Array<Hash>] interface actions
        # @return [PlatformProfile] platform profile object
        def convert_profile_to_platform_profile(profile, actions)
          require_relative '../models/platform_profile'
          require_relative '../models/command_definition'

          profile_data = extract_profile_data(profile)
          profile_commands = profile.respond_to?(:commands) ? profile.commands : (profile[:commands] || profile['commands'] || [])

          # Debug output for profile loading issues (especially Windows)
          Logger.debug("profile class: #{profile.class}", category: :executable)
          Logger.debug("profile_data: #{profile_data.inspect}", category: :executable)
          Logger.debug("profile_commands class: #{profile_commands.class}", category: :executable)
          Logger.debug("profile_commands empty?: #{profile_commands.respond_to?(:empty?) ? profile_commands.empty? : 'N/A'}",
                       category: :executable)
          Logger.debug("profile_commands count: #{profile_commands.respond_to?(:size) ? profile_commands.size : 'N/A'}",
                       category: :executable)
          Logger.debug("profile_commands: #{profile_commands.inspect[0..500]}", category: :executable)
          Logger.debug("actions keys: #{actions.keys.inspect if actions.respond_to?(:keys)}", category: :executable)

          # Build command definitions
          interface_commands_hash = build_interface_commands_hash(actions)
          command_definitions = build_command_definitions(profile_commands, interface_commands_hash)

          Models::PlatformProfile.new(
            **profile_data,
            commands: command_definitions
          )
        end

        # Extract profile data from profile object or hash
        #
        # @param profile [Models::ExecutionProfile, Hash] profile
        # @return [Hash] profile data
        def extract_profile_data(profile)
          if profile.is_a?(Hash)
            {
              name: profile[:name] || profile['name'],
              display_name: profile[:display_name] || profile['display_name'],
              platforms: profile[:platforms] || profile['platforms'],
              shells: profile[:shells] || profile['shells'],
              option_style: profile[:option_style] || profile['option_style'],
              inherits: profile[:inherits] || profile['inherits'],
              executable_name: profile[:executable_name] || profile['executable_name']
            }
          else
            {
              name: profile.name,
              display_name: profile.display_name,
              platforms: profile.platforms,
              shells: profile.shells,
              option_style: profile.option_style,
              inherits: profile.respond_to?(:inherits) ? profile.inherits : nil,
              executable_name: profile.respond_to?(:executable_name) ? profile.executable_name : nil
            }
          end
        end

        # Build interface commands hash from actions
        #
        # @param actions [Array<Hash>] interface actions
        # @return [Hash] commands hash keyed by name
        def build_interface_commands_hash(actions)
          hash = {}
          convert_actions_to_array(actions || []).each do |cmd|
            cmd_name = cmd[:name] || cmd['name']
            hash[cmd_name] = cmd
          end
          hash
        end

        # Build command definitions from profile and interface data
        #
        # @param profile_commands [Array] profile commands
        # @param interface_commands_hash [Hash] interface commands
        # @return [Array<CommandDefinition>] command definitions
        def build_command_definitions(profile_commands, interface_commands_hash)
          if profile_commands.nil? || profile_commands.empty?
            # Use interface actions directly
            interface_commands_hash.map do |_cmd_name, cmd_hash|
              convert_hash_to_command_definition(cmd_hash)
            end
          else
            # Merge profile commands with interface actions
            profile_commands.map do |cmd_hash|
              cmd_name = cmd_hash[:name] || cmd_hash['name'] || cmd_hash[:subcommand] || cmd_hash['subcommand']
              interface_cmd = interface_commands_hash[cmd_name]
              merged_cmd_hash = interface_cmd ? deep_merge_hashes(interface_cmd, cmd_hash) : cmd_hash
              convert_hash_to_command_definition(merged_cmd_hash)
            end
          end
        end

        # Convert hash to CommandDefinition object
        #
        # @param cmd_hash [Hash] command definition hash
        # @return [CommandDefinition] command definition object
        def convert_hash_to_command_definition(cmd_hash)
          require_relative '../models/command_definition'

          post_options_data = cmd_hash['post_options'] || cmd_hash[:post_options]

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

        # Deep merge two hashes (second hash takes precedence)
        #
        # @param base [Hash] base hash
        # @param override [Hash] override hash
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

        # Convert actions hash to array format
        #
        # @param actions_data [Hash, Array] actions data
        # @return [Array<Hash>] array of command definitions
        def convert_actions_to_array(actions_data)
          return [] if actions_data.nil? || actions_data.empty?

          if actions_data.is_a?(Hash)
            actions_data.map do |command_name, command_def|
              command_def = command_def.to_h
              command_def['name'] ||= command_name.to_s
              command_def
            end
          else
            actions_data.map do |command_def|
              flatten_signature(command_def.to_h)
            end
          end
        end

        # Flatten signature from command definition
        #
        # @param command_def [Hash] command definition
        # @return [Hash] flattened command definition
        def flatten_signature(command_def)
          signature = command_def[:signature] || command_def['signature']
          return command_def unless signature

          signature.each do |key, value|
            if [:inputs, 'inputs'].include?(key) && value.is_a?(Hash)
              value.each do |nested_key, nested_value|
                target_key = nested_key.to_s == 'inputs' ? 'arguments' : nested_key.to_s
                command_def[target_key.to_sym] = nested_value unless [:signature, 'signature'].include?(nested_key)
              end
            else
              command_def[key] = value unless [:signature, 'signature'].include?(key)
            end
          end
          command_def.delete(:signature)
          command_def.delete('signature')
          command_def
        end
      end
    end
  end
end
