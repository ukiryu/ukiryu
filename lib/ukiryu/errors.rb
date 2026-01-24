# frozen_string_literal: true

module Ukiryu
  # Base error class
  class Error < StandardError; end

  # Shell detection errors
  class UnknownShellError < Error; end

  # Platform errors
  class UnsupportedPlatformError < Error; end

  # Type validation errors
  class ValidationError < Error; end

  # Profile errors
  class ProfileNotFoundError < Error; end
  class ProfileLoadError < Error; end

  # Definition loading errors
  class DefinitionError < Error; end
  class DefinitionNotFoundError < DefinitionError; end
  class DefinitionLoadError < DefinitionError; end
  class DefinitionValidationError < DefinitionError; end

  # Definition loading errors (legacy, use DefinitionError instead)
  class LoadError < Error; end

  # Tool errors
  class ToolNotFoundError < Error; end
  class ExecutableNotFoundError < Error; end

  # Execution errors
  class ExecutionError < Error; end
  class TimeoutError < Error; end

  # Version errors
  class VersionDetectionError < Error; end
end
