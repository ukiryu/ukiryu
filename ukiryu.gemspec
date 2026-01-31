# frozen_string_literal: true

require_relative 'lib/ukiryu/version'

Gem::Specification.new do |spec|
  spec.name          = 'ukiryu'
  spec.version       = Ukiryu::VERSION
  spec.authors       = ['Ribose Inc.']
  spec.email         = ['open.source@ribose.com']

  spec.summary       = 'The "OpenAPI" for Command Line Interfaces'
  spec.description   = <<~DESCRIPTION
    Ukiryu is a platform-adaptive command execution framework that transforms CLI tools
    into declarative APIs. It provides the "OpenAPI" for command-line interfaces,
    enabling cross-platform tool integration with type safety and structured results.

    Key features:

    * Declarative YAML profiles define tool behavior, eliminating hardcoded command strings
    * Platform-adaptive execution across macOS, Linux, and Windows
    * Shell-aware command formatting for bash, zsh, fish, PowerShell, and cmd
    * Type-safe parameter validation with automatic coercion
    * Version routing support with semantic version matching (via Versionian)
    * Interface contracts allow multiple tools to implement the same abstract API
    * Structured Result objects with success/failure information instead of parsing stdout
    * Comprehensive error handling under Ukiryu::Errors namespace

    The Ukiryu ecosystem consists of:

    * ukiryu gem - The runtime framework
    * ukiryu/register - Collection of YAML tool profiles
    * ukiryu/schemas - JSON Schema for validation

    Use Ukiryu to integrate command-line tools like ImageMagick, FFmpeg, Inkscape,
    Ghostscript, and more into your Ruby applications with consistent,
    predictable interfaces.
  DESCRIPTION

  spec.homepage      = 'https://github.com/ukiryu/ukiryu'
  spec.license       = 'BSD-2-Clause'

  spec.bindir        = 'exe'
  spec.executables   = ['ukiryu']
  spec.require_paths = ['lib']

  # Use Dir.glob instead of git ls-files for CI compatibility
  spec.files         = Dir.glob('{lib,exe,README.adoc,LICENSE,BSDL,*.md}/**/*')
                          .reject { |f| File.directory?(f) || f.match?(%r{^spec/}) }
  spec.test_files    = Dir.glob('spec/**/*')
                          .reject { |f| File.directory?(f) }
  spec.required_ruby_version = '>= 2.7.0'

  # Core dependencies
  spec.add_dependency 'git', '~> 3.0'
  spec.add_dependency 'json-schema'
  spec.add_dependency 'lutaml-model', '~> 0.7.0'
  spec.add_dependency 'lutaml-xsd', '~> 0.1.0'
  spec.add_dependency 'thor'
  spec.add_dependency 'versionian', '~> 0.1'
end
