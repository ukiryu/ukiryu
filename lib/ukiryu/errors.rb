# frozen_string_literal: true

module Ukiryu
  # Errors namespace - all error classes live here
  module Errors
    # Base error class with helpful context
    class Error < StandardError
      # Get suggestions for resolving this error
      #
      # @return [Array<String>] suggestions for the user
      def suggestions
        []
      end
    end

    # Shell detection errors
    class UnknownShellError < Error
      def suggestions
        [
          'Supported shells: bash, zsh, fish, sh, dash, tcsh, powershell, cmd',
          'Platform groups: :unix (all Unix shells), :windows, :powershell',
          'Set explicitly: Ukiryu.configure { |c| c.default_shell = :bash }'
        ]
      end
    end

    # Platform errors
    class UnsupportedPlatformError < Error
      def suggestions
        [
          'Ukiryu supports: macOS, Linux, Windows',
          "Current platform: #{RUBY_PLATFORM}",
          'Check if running on a supported operating system'
        ]
      end
    end

    # Type validation errors
    class ValidationError < Error
      def suggestions
        [
          'Check the parameter type against the tool definition',
          'Verify value is within allowed range',
          'Ensure value is in the allowed values list'
        ]
      end
    end

    # Profile errors
    class ProfileNotFoundError < Error
      def suggestions
        [
          'Check tool definition has profile for your platform',
          'Verify tool definition has profile for your shell',
          'Try specifying platform/shell explicitly'
        ]
      end
    end

    class ProfileLoadError < Error
      def suggestions
        [
          'Verify YAML syntax is correct',
          'Check profile structure matches schema',
          'Review error message for specific issue'
        ]
      end
    end

    # Definition loading errors
    class DefinitionError < Error; end

    class DefinitionNotFoundError < DefinitionError
      def suggestions
        [
          'Verify file path is correct',
          'Check file has .yaml extension',
          'Use absolute path if relative path fails'
        ]
      end
    end

    class DefinitionLoadError < DefinitionError
      def suggestions
        [
          'Validate YAML syntax',
          'Check file is readable',
          'Verify file encoding is UTF-8'
        ]
      end
    end

    class DefinitionValidationError < DefinitionError
      def suggestions
        [
          "Run 'ukiryu validate' for detailed errors",
          'Compare with schema definition',
          'Check tool definition examples'
        ]
      end
    end

    # Definition loading errors (legacy, use DefinitionError instead)
    class LoadError < Error; end

    # Tool errors
    class ToolNotFoundError < Error
      def suggestions
        [
          'Check tool name spelling',
          'Verify register path is correct',
          'List available tools: Ukiryu::Register.tool_names'
        ]
      end
    end

    class ExecutableNotFoundError < Error
      def suggestions
        [
          'Install the tool (e.g., brew install imagemagick)',
          'Add executable to PATH',
          'Configure search_paths in tool definition'
        ]
      end
    end

    # Execution errors
    class ExecutionError < Error
      def suggestions
        [
          'Check e.result.exit_status for exit code',
          'Check e.result.stderr for error message',
          'Verify parameters are correct'
        ]
      end
    end

    class TimeoutError < Error
      def initialize(message = nil, timeout: nil)
        super(message)
        @timeout = timeout
      end

      attr_reader :timeout

      def suggestions
        [
          'Increase timeout parameter',
          'Check UKIRYU_TIMEOUT environment variable',
          'Verify tool is not hanging'
        ]
      end
    end

    # Version errors
    class VersionDetectionError < Error
      def suggestions
        [
          'Verify tool is installed correctly',
          'Check version_detection command in tool definition',
          'Test version command manually: tool --version'
        ]
      end
    end
  end
end
