# frozen_string_literal: true

require 'digest'
require_relative 'metadata'

module Ukiryu
  module Definition
    # Cache for tool definitions with hot-reload support
    #
    # This class provides caching for tool definitions with automatic
    # invalidation based on file modification time and TTL.
    class DefinitionCache
      # Default cache TTL in seconds (5 minutes)
      DEFAULT_TTL = 300

      # Cache entry structure
      class Entry
        attr_reader :definition, :mtime, :loaded_at, :source_key

        def initialize(definition, mtime: nil, source_key: nil)
          @definition = definition
          @mtime = mtime
          @loaded_at = Time.now
          @source_key = source_key || generate_source_key(definition)
        end

        # Check if entry is stale
        #
        # @param ttl [Integer] time to live in seconds
        # @return [Boolean] true if entry is stale
        def stale?(ttl: DEFAULT_TTL)
          # Check TTL
          return true if Time.now - @loaded_at > ttl

          # Check mtime for file-based definitions
          if @mtime && @definition.respond_to?(:path)
            path = @definition.path
            return true if path && File.exist?(path) && File.mtime(path) > @mtime
          end

          false
        end

        # Refresh the entry
        #
        # @return [Entry] refreshed entry
        def refresh
          if @definition.respond_to?(:load_definition)
            # Reload from metadata
            new_def = @definition.load_definition
            Entry.new(new_def, mtime: new_def.mtime, source_key: @source_key)
          else
            # Can't refresh, return as-is
            self
          end
        end

        private

        def generate_source_key(definition)
          # Generate cache key from definition
          if definition.respond_to?(:name) && definition.respond_to?(:version)
            Digest::SHA256.hexdigest("#{definition.name}/#{definition.version}")
          else
            Digest::SHA256.hexdigest(definition.object_id.to_s)
          end
        end
      end

      # Singleton instance
      @instance = nil

      class << self
        # Get the singleton instance
        #
        # @return [DefinitionCache] the cache instance
        def instance
          @instance ||= new
        end

        # Reset the singleton (useful for testing)
        def reset_instance
          @instance = nil
        end
      end

      # Initialize a new cache
      #
      # @param ttl [Integer] default time-to-live in seconds
      def initialize(ttl: DEFAULT_TTL)
        @cache = {}
        @ttl = ttl
        @refresh_strategy = :lazy
        @mutex = Mutex.new
      end

      # Get a cached definition
      #
      # @param key [String] the cache key
      # @return [Models::ToolDefinition, nil] the cached definition, or nil
      def get(key)
        @mutex.synchronize do
          entry = @cache[key]
          return nil unless entry

          # Check staleness
          if entry.stale?(ttl: @ttl)
            if @refresh_strategy == :lazy
              # Refresh and return
              entry = entry.refresh
              @cache[key] = entry if entry
            else
              # Return stale entry (eager mode refreshes in background)
            end
          end
          entry.definition
        end
      end

      # Set a cached definition
      #
      # @param key [String] the cache key
      # @param definition [Models::ToolDefinition] the definition to cache
      # @param metadata [DefinitionMetadata, nil] optional metadata for mtime tracking
      # @return [Models::ToolDefinition] the cached definition
      def set(key, definition, metadata: nil)
        @mutex.synchronize do
          mtime = metadata&.mtime
          entry = Entry.new(definition, mtime: mtime)
          @cache[key] = entry
          definition
        end
      end

      # Check if a key exists in cache
      #
      # @param key [String] the cache key
      # @return [Boolean] true if key exists
      def key?(key)
        @cache.key?(key)
      end

      # Invalidate a cache entry
      #
      # @param key [String] the cache key to invalidate
      # @return [Boolean] true if entry was invalidated
      def invalidate(key)
        @mutex.synchronize do
          !@cache.delete(key).nil?
        end
      end

      # Clear all cache entries
      #
      # @return [Integer] number of entries cleared
      def clear
        @mutex.synchronize do
          count = @cache.size
          @cache.clear
          count
        end
      end

      # Get cache statistics
      #
      # @return [Hash] cache statistics
      def stats
        {
          size: @cache.size,
          ttl: @ttl,
          refresh_strategy: @refresh_strategy,
          entries: @cache.keys
        }
      end

      # Check if a cache entry is stale
      #
      # @param key [String] the cache key
      # @return [Boolean] true if entry is stale
      def stale?(key)
        entry = @cache[key]
        return true unless entry

        entry.stale?(ttl: @ttl)
      end

      # Set the refresh strategy
      #
      # @param strategy [Symbol] :lazy or :eager
      def refresh_strategy=(strategy)
        raise ArgumentError, "Invalid refresh strategy: #{strategy}" unless %i[lazy eager never].include?(strategy)

        @refresh_strategy = strategy
      end

      # Get the current refresh strategy
      #
      # @return [Symbol] the refresh strategy
      attr_reader :refresh_strategy

      # Set the cache TTL
      #
      # @param ttl [Integer] time-to-live in seconds

      # Get the current TTL
      #
      # @return [Integer] the TTL in seconds
      attr_accessor :ttl

      # Refresh all stale entries
      #
      # @return [Integer] number of entries refreshed
      def refresh_stale
        @mutex.synchronize do
          count = 0
          @cache.each do |key, entry|
            if entry.stale?(ttl: @ttl)
              @cache[key] = entry.refresh
              count += 1
            end
          end
          count
        end
      end

      # Prune stale entries
      #
      # @return [Integer] number of entries pruned
      def prune
        @mutex.synchronize do
          stale_keys = @cache.select { |_, entry| entry.stale?(ttl: @ttl) }.keys
          stale_keys.each { |key| @cache.delete(key) }
          stale_keys.size
        end
      end
    end
  end
end
