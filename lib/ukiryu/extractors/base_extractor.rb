# frozen_string_literal: true

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
      # @param command [Array<String>] the command to execute
      # @return [Hash] result with :stdout, :stderr, :exit_status keys
      def execute_command(command)
        require 'open3'

        stdout, stderr, status = Open3.capture3(*command)
        {
          stdout: stdout,
          stderr: stderr,
          exit_status: status.exitstatus
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
