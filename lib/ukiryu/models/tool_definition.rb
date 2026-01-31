# frozen_string_literal: true

module Ukiryu
  module Models
    # Tool definition loaded from YAML profile
    #
    # @example
    #   tool = ToolDefinition.from_yaml(yaml_string)
    #   profile = tool.compatible_profile
    class ToolDefinition < Lutaml::Model::Serializable
      attribute :ukiryu_schema, :string
      attribute :self_uri, :string
      attribute :name, :string
      attribute :display_name, :string
      attribute :homepage, :string
      attribute :version, :string
      attribute :implements, :string, collection: true, initialize_empty: true # v2: array of interface names
      attribute :aliases, :string, collection: true, initialize_empty: true
      attribute :invocation, Invocation # v2: invocation configuration
      attribute :profiles, PlatformProfile, collection: true
      attribute :version_detection, VersionDetection
      attribute :components, Components # Register of reusable definitions

      key_value do
        map 'ukiryu_schema', to: :ukiryu_schema
        map '$self', to: :self_uri
        map 'name', to: :name
        map 'display_name', to: :display_name
        map 'homepage', to: :homepage
        map 'version', to: :version
        map 'implements', to: :implements # v2: array mapping
        map 'aliases', to: :aliases
        map 'invocation', to: :invocation # v2: invocation mapping
        map 'profiles', to: :profiles
        map 'version_detection', to: :version_detection
        map 'components', to: :components
      end

      # Get compatible profile for current platform/shell
      #
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      # @return [PlatformProfile, nil] the compatible profile
      def compatible_profile(platform: nil, shell: nil)
        platform ||= Ukiryu::Platform.detect
        shell ||= Ukiryu::Shell.detect
        return nil unless platform && shell

        return nil if profiles.nil? || profiles.empty?

        profiles.find do |p|
          p.is_a?(PlatformProfile) && p.compatible?(platform.to_sym, shell.to_sym)
        end
      end

      # Check if tool implements an interface
      #
      # @param interface_name [String, Symbol] the interface name
      # @return [Boolean] true if implements
      def implements?(interface_name)
        # v2: implements is an array, check if it contains the interface
        # v1: implements is a string, check for equality
        interface_sym = interface_name.to_s.to_sym
        implements_any?(interface_sym)
      end

      # Check if tool implements any of the given interfaces
      #
      # @param interface_names [Array<Symbol>] the interface names to check
      # @return [Boolean] true if implements any of the given interfaces
      def implements_any?(*interface_names)
        return false if implements.nil? || implements.empty?

        interface_syms = interface_names.flatten.map(&:to_sym)
        implements_syms = implements.map(&:to_sym)

        (interface_syms & implements_syms).any?
      end

      # Get all interfaces this tool implements
      #
      # @return [Array<String>] array of interface names
      def interfaces
        implements || []
      end

      # Check if tool is available on a platform
      #
      # @param platform [Symbol] the platform
      # @return [Boolean] true if available
      def available_on?(platform)
        return true if profiles.empty?

        profiles.any? { |p| p.is_a?(PlatformProfile) && p.supports_platform?(platform) }
      end

      # Resolve profile inheritance
      #
      # Merges parent profile commands into child profiles that have `inherits` set.
      # The child profile's commands take precedence over parent commands.
      #
      # @return [self] returns self for chaining
      def resolve_inheritance!
        return self unless profiles

        profiles.each do |profile|
          next unless profile.inherits

          # Find parent profile by name
          parent_profile = profiles.find { |p| p.name == profile.inherits }
          next unless parent_profile

          # Merge parent commands into child (child takes precedence)
          parent_commands = parent_profile.commands || []
          child_commands = profile.commands || []

          # Create a map of child commands by name for quick lookup
          child_commands_map = child_commands.to_h { |c| [c.name, c] }

          # Add parent commands that don't exist in child
          merged_commands = child_commands.dup
          parent_commands.each do |parent_cmd|
            merged_commands << parent_cmd unless child_commands_map.key?(parent_cmd.name)
          end

          # Update profile commands and clear index so it rebuilds on next access
          profile.commands = merged_commands
          profile.clear_commands_index!
        end

        self
      end

      # Get the schema version
      #
      # @return [String, nil] the schema version (e.g., "1.0", "1.1", "1.2")
      def schema_version
        ukiryu_schema
      end

      # Get the self URI
      #
      # @return [String, nil] the self URI
      attr_reader :self_uri

      # Check if a specific schema version is specified
      #
      # @param version [String] the version to check
      # @return [Boolean] true if this is the schema version
      def schema_version?(version)
        ukiryu_schema == version
      end
    end
  end
end
