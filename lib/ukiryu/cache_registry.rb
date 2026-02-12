# frozen_string_literal: true

module Ukiryu
  # Centralized cache registry for managing all Ukiryu caches.
  #
  # Provides a single point of control for:
  # - Clearing all caches (useful for testing)
  # - Getting cache statistics (useful for debugging)
  # - Accessing individual caches by name
  #
  # @example Clear all caches
  #   Ukiryu::CacheRegistry.clear_all
  #
  # @example Get cache statistics
  #   Ukiryu::CacheRegistry.stats
  #   # => { tool_cache: { size: 10, hits: 100, misses: 5 }, ... }
  #
  module CacheRegistry
    class << self
      # Get all registered caches
      #
      # @return [Array<Cache>] list of cache instances
      def caches
        [
          ToolCache.cache,
          Definition::Loader.profile_cache
        ].compact
      end

      # Clear all registered caches
      #
      # @return [void]
      def clear_all
        caches.each(&:clear)
        nil
      end

      # Get statistics for all caches
      #
      # @return [Hash] cache name => stats hash
      def stats
        {
          tool_cache: cache_stats(ToolCache.cache),
          definition_cache: cache_stats(Definition::Loader.profile_cache)
        }.compact
      end

      private

      # Get stats for a single cache
      #
      # @param cache [Cache, nil] the cache instance
      # @return [Hash, nil] stats hash or nil if cache is nil
      def cache_stats(cache)
        return nil unless cache

        {
          size: cache.size,
          max_size: cache.max_size
        }
      end
    end
  end
end
