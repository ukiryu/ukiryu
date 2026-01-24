# frozen_string_literal: true

require_relative 'ukiryu/version'
require_relative 'ukiryu/errors'

# Core modules
require_relative 'ukiryu/platform'
require_relative 'ukiryu/shell'
require_relative 'ukiryu/runtime'
require_relative 'ukiryu/execution_context'
require_relative 'ukiryu/type'
require_relative 'ukiryu/executor'
require_relative 'ukiryu/register'
require_relative 'ukiryu/tool'
require_relative 'ukiryu/options_builder'
require_relative 'ukiryu/schema_validator'
require_relative 'ukiryu/io'

# Definition loading
require_relative 'ukiryu/definition'

# Models - OOP representation of YAML profiles
require_relative 'ukiryu/models'

# New OOP modules
require_relative 'ukiryu/tools'
require_relative 'ukiryu/options/base'
require_relative 'ukiryu/response/base'
require_relative 'ukiryu/action/base'
require_relative 'ukiryu/validation'

# Extractors
require_relative 'ukiryu/extractors/extractor'

# CLI (optional, only load if thor is available)
begin
  require 'thor'
  require_relative 'ukiryu/cli'
rescue LoadError
  # Thor not available, CLI will not be available
end

module Ukiryu
  class << self
    # Configure global Ukiryu settings
    def configure
      yield configuration
    end

    # Get global configuration
    def configuration
      @configuration ||= Configuration.new
    end

    # Reset configuration (mainly for testing)
    def reset_configuration
      @configuration = nil
      Shell.reset
      Runtime.instance.reset!
      ExecutionContext.reset_current!
    end
  end

  # Configuration class for global settings
  class Configuration
    attr_accessor :default_shell, :register_path

    def initialize
      @default_shell = nil # Auto-detect by default
      @register_path = nil
    end
  end
end
