# frozen_string_literal: true

require_relative 'lib/ukiryu/version'

Gem::Specification.new do |spec|
  spec.name          = 'ukiryu'
  spec.version       = Ukiryu::VERSION
  spec.authors       = ['Ribose Inc.']
  spec.email         = ['open.source@ribose.com']

  spec.summary       = 'Platform-adaptive command execution framework'
  spec.description   = <<~DESCRIPTION
    Ukiryu is a Ruby framework for creating robust, cross-platform wrappers
    around external command-line tools through declarative YAML profiles.
    Ukiryu turns external CLIs into Ruby APIs with explicit type safety,
    shell detection, and platform profiles.
  DESCRIPTION

  spec.homepage      = 'https://github.com/riboseinc/ukiryu'
  spec.license       = 'BSD-2-Clause'

  spec.bindir        = 'exe'
  spec.executables   = ['ukiryu']
  spec.require_paths = ['lib']
  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^spec/})
  end
  spec.test_files = `git ls-files -- {spec}/*`.split("\n")
  spec.required_ruby_version = '>= 2.7.0'

  # Core dependencies
  spec.add_dependency 'git', '~> 3.0'
  spec.add_dependency 'lutaml-model', '~> 0.7'
  spec.add_dependency 'thor', '~> 1.0'

  # Optional runtime dependency for YAML schema validation
  spec.add_dependency 'json-schema', '~> 4.0'
end
