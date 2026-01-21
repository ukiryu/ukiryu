# frozen_string_literal: true

require_relative "ukiryu/version"
require_relative "ukiryu/errors"

# Core modules
require_relative "ukiryu/platform"
require_relative "ukiryu/shell"
require_relative "ukiryu/type"
require_relative "ukiryu/executor"
require_relative "ukiryu/registry"
require_relative "ukiryu/tool"
require_relative "ukiryu/schema_validator"

# CLI (optional, only load if thor is available)
begin
  require "thor"
  require_relative "ukiryu/cli"
rescue LoadError
  # Thor not available, CLI will not be available
end

module Ukiryu
  class Error < StandardError; end

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
    end
  end

  # Configuration class for global settings
  class Configuration
    attr_accessor :default_shell
    attr_accessor :registry_path

    def initialize
      @default_shell = nil # Auto-detect by default
      @registry_path = nil
    end
  end
end
