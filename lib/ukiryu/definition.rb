# frozen_string_literal: true

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
    # Autoload nested classes
    autoload :Source, 'ukiryu/definition/source'
    autoload :FileSource, 'ukiryu/definition/sources/file'
    autoload :StringSource, 'ukiryu/definition/sources/string'
    autoload :Loader, 'ukiryu/definition/loader'
    autoload :Metadata, 'ukiryu/definition/metadata'
    autoload :DefinitionMetadata, 'ukiryu/definition/metadata' # Alias for Metadata
    autoload :Discovery, 'ukiryu/definition/discovery'
    autoload :VersionResolver, 'ukiryu/definition/version_resolver'
    autoload :DefinitionCache, 'ukiryu/definition/definition_cache'
    autoload :DefinitionComposer, 'ukiryu/definition/definition_composer'
    autoload :ValidationResult, 'ukiryu/definition/validation_result'
    autoload :DefinitionValidator, 'ukiryu/definition/definition_validator'
    autoload :LintIssue, 'ukiryu/definition/lint_issue'
    autoload :DefinitionLinter, 'ukiryu/definition/definition_linter'
    autoload :DocumentationGenerator, 'ukiryu/definition/documentation_generator'

    # Nested Sources namespace
    module Sources
      autoload :FileSource, 'ukiryu/definition/sources/file'
      autoload :StringSource, 'ukiryu/definition/sources/string'
    end
  end
end

# Export classes for convenience
Ukiryu::Definition::FileSource = Ukiryu::Definition::Sources::FileSource
Ukiryu::Definition::StringSource = Ukiryu::Definition::Sources::StringSource
