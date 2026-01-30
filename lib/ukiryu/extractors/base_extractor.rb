# frozen_string_literal: true

require_relative '../environment'
require_relative '../executor'

module Ukiryu
  module Extractors
    # Base class for definition extraction strategies
    #
    # Each extraction strategy implements a different approach to
    # extracting tool definitions from CLI tools.
    #
    # @abstract Subclasses must implement the `extract` method
    class BaseExtractor
      # Initialize the extractor
      #
      # @param tool_name [String, Symbol] the tool name
      # @param options [Hash] extraction options
      def initialize(tool_name, options = {})
        @tool_name = tool_name
        @options = options
      end

      # Extract definition from the tool
      #
      # Subclasses must implement this method
      #
      # @return [String, nil] the YAML definition or nil if extraction failed
      # @raise [NotImplementedError] if not implemented in subclass
      def extract
        raise NotImplementedError, "#{self.class} must implement #extract"
      end

      # Check if this extractor can extract from the tool
      #
      # @return [Boolean] true if extraction is possible
      def available?
        raise NotImplementedError, "#{self.class} must implement #available?"
      end

      private

      # Execute a command and capture output
      #
      # All command execution goes through the Environment system to ensure
      # consistent environment variable handling, shell escaping, and timeout
      # management across the entire codebase.
      #
      # @param command [Array<String>] the command to execute (array form)
      # @param env [Environment, Hash] optional environment overrides
      # @return [Hash] result with :stdout, :stderr, :exit_status keys
      def execute_command(command, env = nil)
        require_relative '../shell'

        # Build environment using Environment system
        environment = env.is_a?(Environment) ? env : Environment.from_env

        # Detect shell for internal extractor utilities
        shell_class = Shell.detect

        # Extract executable and args from command array
        executable = command.first
        args = command[1..]

        # Execute through Executor (uses Environment system internally)
        result = Executor.execute(executable, args, env: environment, shell: shell_class, allow_failure: true)

        {
          stdout: result.stdout,
          stderr: result.stderr,
          exit_status: result.status
        }
      rescue Errno::ENOENT
        # Command not found
        {
          stdout: '',
          stderr: 'Command not found',
          exit_status: 127
        }
      end
    end
  end
end
