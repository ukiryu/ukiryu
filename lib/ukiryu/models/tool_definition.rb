# frozen_string_literal: true

require 'lutaml/model'
require_relative 'platform_profile'
require_relative 'version_detection'
require_relative 'search_paths'
require_relative 'components'

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
      attribute :implements, :string
      attribute :aliases, :string, collection: true, default: []
      attribute :timeout, :integer, default: 90
      attribute :profiles, PlatformProfile, collection: true
      attribute :version_detection, VersionDetection
      attribute :search_paths, SearchPaths
      attribute :components, Components  # Registry of reusable definitions

      yaml do
        map_element 'ukiryu_schema', to: :ukiryu_schema
        map_element '$self', to: :self_uri
        map_element 'name', to: :name
        map_element 'display_name', to: :display_name
        map_element 'homepage', to: :homepage
        map_element 'version', to: :version
        map_element 'implements', to: :implements
        map_element 'aliases', to: :aliases
        map_element 'timeout', to: :timeout
        map_element 'profiles', to: :profiles
        map_element 'version_detection', to: :version_detection
        map_element 'search_paths', to: :search_paths
        map_element 'components', to: :components
      end

      # Get compatible profile for current platform/shell
      #
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      # @return [PlatformProfile, nil] the compatible profile
      def compatible_profile(platform: nil, shell: nil)
        require_relative '../platform'
        require_relative '../shell'

        platform ||= Platform.detect
        shell ||= Shell.detect
        return nil unless platform && shell

        return nil if profiles.empty?

        profiles.find do |p|
          p.is_a?(PlatformProfile) && p.compatible?(platform.to_sym, shell.to_sym)
        end
      end

      # Check if tool implements an interface
      #
      # @param interface_name [String, Symbol] the interface name
      # @return [Boolean] true if implements
      def implements?(interface_name)
        implements == interface_name.to_s
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
      def self_uri
        @self_uri
      end

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
