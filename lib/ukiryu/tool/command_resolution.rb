# frozen_string_literal: true

module Ukiryu
  class Tool
    # Command resolution and routing for hierarchical tools
    #
    # Provides methods to resolve command paths in tools with routing,
    # such as git where commands are organized hierarchically
    # (e.g., 'remote:add', 'branch:delete').
    #
    # @api private
    module CommandResolution
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
      # @param execution_timeout [Integer] timeout in seconds (required)
      # @param params [Hash] action parameters
      # @return [Executor::Result] the execution result
      #
      # @example
      #   tool.execute_action(['remote', 'add'], {name: 'origin', url: 'https://...'}, execution_timeout: 90)
      #
      def execute_action(path, execution_timeout:, **params)
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
        execute_with_config(resolution[:executable], args, action, params, execution_timeout: execution_timeout, stdin: stdin)
      end

      # Execute a command with root-path notation (for hierarchical tools)
      #
      # Root-path uses ':' to separate levels, e.g., 'remote:add' -> ['remote', 'add']
      # This provides a cleaner API for executing routed actions.
      #
      # @param root_path [String, Symbol] the action path with ':' separator (e.g., 'remote:add')
      # @param execution_timeout [Integer] timeout in seconds for command execution (required)
      # @param params [Hash] action parameters
      # @return [Executor::Result] the execution result
      #
      # @example Root-path notation
      #   tool.execute('remote:add', {name: 'origin', url: 'https://...'}, execution_timeout: 90)
      #   tool.execute('branch:delete', {branch_name: 'feature'}, execution_timeout: 90)
      #   tool.execute('stash:save', {message: 'WIP'}, execution_timeout: 90)
      #
      # @example Simple command (backward compatible)
      #   tool.execute(:convert, {inputs: ['image.png'], output: 'output.jpg'}, execution_timeout: 90)
      #
      def execute(root_path, execution_timeout:, **params)
        # Check if this is a root-path (contains ':')
        if root_path.is_a?(String) && root_path.include?(':')
          path = root_path.split(':').map(&:strip)
          execute_action(path, execution_timeout: execution_timeout, **params)
        else
          # Use simple execute for regular commands
          execute_simple(root_path, execution_timeout: execution_timeout, **params)
        end
      end

      # Find the best matching command profile
      #
      # Strategy:
      # 1. If multiple profiles exist, find one matching current platform/shell
      # 2. If single profile exists, use it (PATH discovery is primary)
      # 3. If no matching profile found among multiple, raise error
      #
      # @return [Models::CommandProfile, nil] the compatible profile
      # @raise [ProfileNotFoundError] if no compatible profile found
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
    end
  end
end
