# frozen_string_literal: true

module Ukiryu
  class Config
    # Resolves configuration values using priority chain
    # Priority: CLI options > ENV > programmatic > defaults
    class OverrideResolver
      attr_reader :defaults, :programmatic, :env, :cli

      def initialize(defaults: {}, programmatic: {}, env: {}, cli: {})
        @defaults = defaults
        @programmatic = programmatic
        @env = env
        @cli = cli
      end

      # Resolve a single value using priority chain
      # Uses .key? to properly handle false values
      def resolve(key)
        return @cli[key] if @cli.key?(key)
        return @env[key] if @env.key?(key)
        return @programmatic[key] if @programmatic.key?(key)

        @defaults[key]
      end

      # Update programmatic value
      def set_programmatic(key, value)
        @programmatic[key] = value
      end

      # Update CLI option value
      def set_cli(key, value)
        @cli[key] = value
      end

      # Update ENV override
      def set_env(key, value)
        @env[key] = value
      end

      # Check if value is set by CLI
      def cli_set?(key)
        @cli.key?(key)
      end

      # Check if value is set by ENV
      def env_set?(key)
        @env.key?(key)
      end

      # Check if value is set programmatically
      def programmatic_set?(key)
        @programmatic.key?(key)
      end

      # Get the source of a value
      def source_for(key)
        return :cli if @cli.key?(key)
        return :env if @env.key?(key)
        return :programmatic if @programmatic.key?(key)
        return :default if @defaults.key?(key)

        nil
      end
    end
  end
end
