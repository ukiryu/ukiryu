# frozen_string_literal: true

require_relative 'version_detection'

module Ukiryu
  module Models
    # ImplementationVersion model for a specific version of a tool implementation.
    #
    # An ImplementationVersion contains the actual command definitions for
    # a specific version of an implementation (e.g., GNU gzip 1.12).
    #
    # @attr implements [String] Interface this implements (e.g., "gzip/1.0")
    # @attr version [String] Version string
    # @attr display_name [String] Human-readable name
    # @attr aliases [Array<String>] Aliases for this implementation
    # @attr execution_profiles [Array<ExecutionProfile>] Platform/shell profiles
    # @attr version_detection [VersionDetection] Version detection configuration
    class ImplementationVersion
      attr_reader :implements, :version, :display_name, :aliases, :execution_profiles, :version_detection

      # @param implements [String] Interface this implements
      # @param version [String] Version string
      # @param display_name [String, nil] Human-readable name
      # @param aliases [Array<String>] Aliases for this implementation
      # @param execution_profiles [Array<Hash>] Execution profile definitions
      # @param version_detection [VersionDetection, nil] Version detection configuration
      def initialize(implements:, version:, execution_profiles:, display_name: nil, aliases: [], version_detection: nil)
        @implements = implements
        @version = version
        @display_name = display_name || "#{implements} #{version}"
        @aliases = Array(aliases).map(&:to_s)
        @execution_profiles = execution_profiles
        @version_detection = version_detection
        freeze
      end

      # Get compatible profile for platform and shell
      #
      # @param platform [Symbol, String] Target platform
      # @param shell [Symbol, String] Target shell
      # @return [Hash, nil] Compatible profile or nil
      def compatible_profile(platform:, shell:)
        platform_str = platform.to_s
        shell_str = shell.to_s

        profile = @execution_profiles.find do |prof|
          platforms = Array(prof[:platforms] || prof[:platform]).map(&:to_s)
          shells = Array(prof[:shells] || prof[:shell]).map(&:to_s)

          platforms.include?(platform_str) && shells.include?(shell_str)
        end

        # Debug output for profile selection
        if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (ENV['CI'] && defined?(Ukiryu::Platform) && Ukiryu::Platform.windows?)
          warn "[UKIRYU DEBUG compatible_profile] platform=#{platform_str}, shell=#{shell_str}"
          warn "[UKIRYU DEBUG compatible_profile] Found profile: #{profile ? (profile[:name] || profile['name']) : 'nil'}"
          if profile
            warn "[UKIRYU DEBUG compatible_profile] Profile inherits: #{profile[:inherits] || profile['inherits']}"
            warn "[UKIRYU DEBUG compatible_profile] Profile commands nil?: #{profile[:commands].nil?}"
            warn "[UKIRYU DEBUG compatible_profile] Profile commands empty?: #{(profile[:commands] || []).empty?}"
          end
        end

        return nil unless profile

        # Resolve profile inheritance at hash level
        # If profile has 'inherits', copy commands from parent profile
        inherits = profile[:inherits] || profile['inherits']
        if inherits
          parent_profile = @execution_profiles.find do |prof|
            prof_name = prof[:name] || prof['name']
            prof_name.to_s == inherits.to_s
          end

          if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (ENV['CI'] && defined?(Ukiryu::Platform) && Ukiryu::Platform.windows?)
            warn "[UKIRYU DEBUG compatible_profile] Looking for parent '#{inherits}': #{parent_profile ? 'found' : 'not found'}"
          end

          if parent_profile && (profile[:commands].nil? || profile[:commands].empty?)
            # Copy parent's commands to child profile (without modifying original)
            parent_commands = parent_profile[:commands] || parent_profile['commands']
            # Return a new hash with inherited commands
            profile = profile.dup.merge(commands: parent_commands)
            warn "[UKIRYU DEBUG compatible_profile] Inherited #{parent_commands&.size || 0} commands from parent" if ENV['UKIRYU_DEBUG_EXECUTABLE'] || (ENV['CI'] && defined?(Ukiryu::Platform) && Ukiryu::Platform.windows?)
          end
        end

        profile
      end

      # Get profile by name
      #
      # @param profile_name [Symbol] Profile name
      # @return [Hash, nil] Profile or nil
      def profile(profile_name)
        @execution_profiles.find { |p| p[:name] == profile_name }
      end

      # Load ImplementationVersion from YAML file
      #
      # @param path [String] Path to version YAML file
      # @return [ImplementationVersion] Loaded version
      def self.from_yaml(path)
        require 'psych'
        data = Psych.safe_load_file(path,
                                    permitted_classes: [Symbol, String, Integer, Array, Hash, TrueClass, FalseClass])
        from_hash(data)
      end

      # Create ImplementationVersion from hash
      #
      # @param data [Hash] Version data
      # @return [ImplementationVersion] Created version
      def self.from_hash(data)
        # Extract version_detection if present
        version_detection = if data[:version_detection] || data['version_detection']
                              vd_data = data[:version_detection] || data['version_detection']
                              VersionDetection.from_hash(vd_data)
                            end

        # Extract execution_profiles (also accept 'profiles' for backward compatibility)
        profiles_data = data[:execution_profiles] || data['execution_profiles'] ||
                        data[:profiles] || data['profiles'] || []

        new(
          implements: data[:implements],
          version: data[:version],
          display_name: data[:display_name],
          aliases: data[:aliases] || [],
          execution_profiles: profiles_data,
          version_detection: version_detection
        )
      end

      # String representation
      #
      # @return [String]
      def to_s
        "#{@implements} #{@version}"
      end

      # Inspect representation
      #
      # @return [String]
      def inspect
        "#<Ukiryu::Models::ImplementationVersion #{self} profiles=#{@execution_profiles.length}>"
      end
    end

    # ExecutionProfile model for platform/shell-specific command configuration.
    #
    # An ExecutionProfile defines how commands are formatted and executed
    # for a specific platform and shell combination.
    #
    # @attr name [Symbol] Profile identifier
    # @attr platforms [Array<Symbol>] Supported platforms
    # @attr shells [Array<Symbol>] Supported shells
    # @attr option_style [Symbol] Option formatting style
    # @attr executable_name [String] Base executable name
    # @attr actions [Hash] Command definitions
    class ExecutionProfile
      attr_reader :name, :platforms, :shells, :option_style, :executable_name, :actions

      # @param name [Symbol] Profile identifier
      # @param platforms [Array<Symbol>] Supported platforms
      # @param shells [Array<Symbol>] Supported shells
      # @param option_style [Symbol] Option formatting style
      # @param executable_name [String] Executable name
      # @param actions [Hash] Command definitions
      def initialize(name:, platforms:, shells:, option_style:, executable_name:, actions: {})
        @name = name
        @platforms = Array(platforms).map(&:to_sym)
        @shells = Array(shells).map(&:to_sym)
        @option_style = option_style.to_sym
        @executable_name = executable_name
        @actions = actions.transform_keys(&:to_sym)
        freeze
      end

      # Check if profile is compatible with platform and shell
      #
      # @param platform [Symbol] Target platform
      # @param shell [Symbol] Target shell
      # @return [Boolean] true if compatible
      def compatible?(platform, shell)
        @platforms.include?(platform) && @shells.include?(shell)
      end

      # Get command definition
      #
      # @param action_name [Symbol] Action name
      # @return [Hash, nil] Command definition or nil
      def command(action_name)
        @actions[action_name]
      end

      # Get all command definitions
      #
      # @return [Hash] All commands (alias for actions)
      def commands
        @actions
      end

      # String representation
      #
      # @return [String]
      def to_s
        "#{@name} (#{@platforms.join(',')} / #{@shells.join(',')})"
      end

      # Inspect representation
      #
      # @return [String]
      def inspect
        "#<Ukiryu::Models::ExecutionProfile #{@to_s}>"
      end
    end
  end
end
