# frozen_string_literal: true

module Ukiryu
  module Models
    # Platform-specific profile for a tool
    #
    # @example
    #   profile = PlatformProfile.new(
    #     name: 'default',
    #     platforms: [:macos, :linux],
    #     executable_name: 'ping',
    #     commands: [CommandDefinition.new(...)]
    #   )
    class PlatformProfile < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :display_name, :string
      attribute :platforms, :string, collection: true, initialize_empty: true
      attribute :shells, :string, collection: true, initialize_empty: true
      attribute :option_style, :string, default: 'single_dash_space'
      attribute :executable_name, :string
      attribute :commands, Ukiryu::Models::CommandDefinition, collection: true, initialize_empty: true
      attribute :inherits, :string
      attribute :routing_data, :hash, default: {} # Raw routing from YAML
      attribute :version_requirement, :string # Semantic version requirement (e.g., ">= 2.30")
      attribute :exit_codes, Ukiryu::Models::ExitCodes # Exit code definitions for this profile
      attribute :env_var_sets, :hash, default: {} # Reusable env var sets (e.g., "headless")

      key_value do
        map 'name', to: :name
        map 'display_name', to: :display_name
        map 'platforms', to: :platforms
        map 'shells', to: :shells
        map 'option_style', to: :option_style
        map 'executable_name', to: :executable_name
        map 'commands', to: :commands
        map 'inherits', to: :inherits
        map 'routing', to: :routing_data
        map 'version_requirement', to: :version_requirement
        map 'exit_codes', to: :exit_codes
        map 'env_var_sets', to: :env_var_sets
      end

      # Get the routing table as a Routing model
      #
      # @return [Routing] the routing table
      def routing
        @routing ||= Ukiryu::Models::Routing.new(@routing_data || {})
      end

      # Check if this profile has routing defined
      #
      # @return [Boolean] true if routing table is non-empty
      def routing?
        !@routing_data.nil? && !@routing_data.empty?
      end

      # Check if profile supports a platform
      #
      # @param platform [Symbol] the platform
      # @return [Boolean] true if supported
      def supports_platform?(platform)
        platform_list = cached_platforms_sym
        platform_list.nil? || platform_list.empty? ||
          platform_list.include?(platform.to_sym)
      end

      # Check if profile supports a shell
      #
      # @param shell [Symbol] the shell
      # @return [Boolean] true if supported
      def supports_shell?(shell)
        shell_list = cached_shells_sym
        shell_list.nil? || shell_list.empty? ||
          shell_list.include?(shell.to_sym)
      end

      # Check if profile is compatible with platform and shell
      #
      # @param platform [Symbol] the platform
      # @param shell [Symbol] the shell
      # @return [Boolean] true if compatible
      def compatible?(platform, shell)
        supports_platform?(platform) && supports_shell?(shell)
      end

      # Get a command by name using indexed O(1) lookup
      #
      # @param name [String, Symbol] the command name
      # @return [CommandDefinition, nil] the command
      def command(name)
        return nil unless commands

        build_commands_index unless @commands_index_built
        @commands_index[name.to_s]
      end

      # Get all command names
      #
      # @return [Array<String>] command names
      def command_names
        return [] unless commands

        build_commands_index unless @commands_index_built
        @commands_index.keys
      end

      # Check if universal (supports all)
      #
      # @return [Boolean] true if universal
      def universal?
        (platforms.nil? || platforms.empty?) &&
          (shells.nil? || shells.empty?)
      end

      # Clear the commands index
      #
      # Call this if commands are modified after initial loading
      # (e.g., during inheritance resolution)
      #
      # @api private
      def clear_commands_index!
        @commands_index = nil
        @commands_index_built = false
      end

      private

      # Get platforms as cached symbol array
      #
      # @api private
      def cached_platforms_sym
        @cached_platforms_sym ||= platforms&.map(&:to_sym)
      end

      # Get shells as cached symbol array
      #
      # @api private
      def cached_shells_sym
        @cached_shells_sym ||= shells&.map(&:to_sym)
      end

      # Build the commands index hash for O(1) lookup
      #
      # @api private
      def build_commands_index
        return unless commands

        # Handle both array and single object cases
        # In some cases (e.g., serialization edge cases), commands might be
        # a single CommandDefinition instead of an array
        commands_array = if commands.is_a?(Array)
                           commands
                         elsif commands.respond_to?(:each) && commands.class.name.include?('CommandDefinition')
                           # Single CommandDefinition object - wrap in array
                           [commands]
                         else
                           # Unknown type - try to convert to array
                           Array(commands).compact
                         end

        @commands_index = commands_array.to_h { |c| [c.name, c] }
        @commands_index_built = true
      end
    end
  end
end
