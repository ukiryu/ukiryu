# frozen_string_literal: true

module Ukiryu
  # Cache management for Tool instances
  #
  # Provides centralized cache management for tool instances,
  # with bounded LRU caching to prevent memory bloat.
  #
  # @api private
  module ToolCache
    class << self
      # Get the tools cache (bounded LRU cache)
      #
      # @return [Cache] the tools cache with max 50 entries and 1-hour TTL
      def cache
        @cache ||= Ukiryu::Cache.new(max_size: 50, ttl: 3600)
      end

      # Get a tool from the cache
      #
      # @param key [String] the cache key
      # @return [Tool, nil] the cached tool or nil if not found
      def get(key)
        cache[key]
      end

      # Store a tool in the cache
      #
      # @param key [String] the cache key
      # @param tool [Tool] the tool to cache
      # @return [void]
      def set(key, tool)
        cache[key] = tool
      end

      # Generate a cache key for a tool
      #
      # Cache keys are composed of: name-platform-shell-version
      # to ensure different environments get different cached instances.
      #
      # @param name [String, Symbol] the tool name
      # @param options [Hash] initialization options
      # @option options [Symbol] :platform the platform (defaults to Runtime platform)
      # @option options [Symbol] :shell the shell (defaults to Runtime shell)
      # @option options [String] :version the tool version (defaults to 'latest')
      # @return [String] the cache key
      def cache_key_for(name, options)
        runtime = Ukiryu::Runtime.instance
        platform = options[:platform] || runtime.platform
        shell = options[:shell] || runtime.shell
        version = options[:version] || 'latest'
        "#{name}-#{platform}-#{shell}-#{version}"
      end

      # Clear the tool cache
      #
      # Also clears the Tools::Generator cache.
      #
      # @return [void]
      def clear
        cache.clear
        Ukiryu::Tools::Generator.clear_cache
      end

      # Clear the definition cache only
      #
      # Clears the Definition::Loader cache without clearing tool instances.
      #
      # @return [void]
      def clear_definition_cache
        Ukiryu::Definition::Loader.clear_cache
      end
    end
  end
end
