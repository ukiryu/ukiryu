# frozen_string_literal: true

require_relative 'definition/source'
require_relative 'definition/sources/file'
require_relative 'definition/sources/string'

# Export classes for convenience
Ukiryu::Definition::FileSource = Ukiryu::Definition::Sources::FileSource
Ukiryu::Definition::StringSource = Ukiryu::Definition::Sources::StringSource

require_relative 'definition/loader'
require_relative 'definition/metadata'
require_relative 'definition/discovery'
require_relative 'definition/version_resolver'
require_relative 'definition/definition_cache'
require_relative 'definition/definition_composer'

# Phase 5: Ecosystem - Validation, linting, documentation
require_relative 'definition/validation_result'
require_relative 'definition/definition_validator'
require_relative 'definition/lint_issue'
require_relative 'definition/definition_linter'
require_relative 'definition/documentation_generator'

module Ukiryu
  # Definition loading module
  #
  # Provides functionality for loading tool definitions from various sources:
  # - Files on the filesystem
  # - YAML strings
  # - XDG-compliant system paths
  # - Tool-bundled locations
  # - Central register (existing)
  #
  # @see Ukiryu::Tool::load
  # @see Ukiryu::Tool::load_from_string
  # @see Ukiryu::Definition::Discovery
  module Definition
  end
end
