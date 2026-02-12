# frozen_string_literal: true

module Ukiryu
  # Bounded LRU cache with expiration support
  #
  # This cache provides:
  # - Maximum size limit (evicts oldest entries when limit reached)
  # - Time-to-live (TTL) expiration for entries
  # - Thread-safe operations
  #
  # @example
  #   cache = Cache.new(max_size: 100, ttl: 300)
  #   cache[:tool] = tool_instance
  #   value = cache[:tool]
  #
  class Cache
    # Cache entry with expiration tracking
    #
    # @api private
    class Entry
      attr_reader :value, :created_at, :accessed_at

      def initialize(value)
        @value = value
        @created_at = Time.now
        @accessed_at = @created_at
      end

      def touch!
        @accessed_at = Time.now
      end

      def expired?(ttl)
        return false unless ttl

        (Time.now - @created_at) > ttl
      end
    end

    # Initialize a new cache
    #
    # @param max_size [Integer] maximum number of entries (default: 100)
    # @param ttl [Integer, nil] time-to-live in seconds (nil = no expiration)
    # @option options [Boolean] :thread_safe enable thread-safe operations (default: true)
    def initialize(max_size: 100, ttl: nil, thread_safe: true)
      @max_size = max_size
      @ttl = ttl
      @thread_safe = thread_safe
      @data = {}
      @mutex = Mutex.new if thread_safe
    end

    # @return [Integer] maximum cache size
    attr_reader :max_size

    # @return [Integer, nil] time-to-live in seconds
    attr_reader :ttl

    # Get a value from the cache
    #
    # @param key [Object] the cache key
    # @return [Object, nil] the cached value or nil if not found/expired
    def [](key)
      synchronize do
        entry = @data[key]
        return nil unless entry

        # Check expiration
        if entry.expired?(@ttl)
          @data.delete(key)
          return nil
        end

        # Update access time for LRU
        entry.touch!
        entry.value
      end
    end

    # Set a value in the cache
    #
    # @param key [Object] the cache key
    # @param value [Object] the value to cache
    # @return [Object] the cached value
    def []=(key, value)
      synchronize do
        # Evict oldest entry if at capacity
        evict_if_needed

        @data[key] = Entry.new(value)
        value
      end
    end

    # Check if a key exists in the cache (and is not expired)
    #
    # @param key [Object] the cache key
    # @return [Boolean] true if key exists and is not expired
    def key?(key)
      synchronize do
        entry = @data[key]
        return false unless entry

        if entry.expired?(@ttl)
          @data.delete(key)
          return false
        end

        true
      end
    end

    # Delete a key from the cache
    #
    # @param key [Object] the cache key
    # @return [Object, nil] the deleted value or nil if not found
    def delete(key)
      synchronize do
        entry = @data.delete(key)
        entry&.value
      end
    end

    # Clear all entries from the cache
    #
    # @return [void]
    def clear
      synchronize do
        @data.clear
      end
    end

    # Get the current number of entries
    #
    # @return [Integer] number of entries
    def size
      @data.size
    end

    # Check if the cache is empty
    #
    # @return [Boolean] true if cache is empty
    def empty?
      @data.empty?
    end

    # Get all keys (excluding expired entries)
    #
    # @return [Array<Object>] array of keys
    def keys
      synchronize do
        cleanup_expired
        @data.keys
      end
    end

    # Get cache statistics
    #
    # @return [Hash] statistics about the cache
    def stats
      synchronize do
        cleanup_expired
        {
          size: @data.size,
          max_size: @max_size,
          ttl: @ttl,
          utilization: @data.size.to_f / @max_size
        }
      end
    end

    private

    # Synchronize block if thread-safe mode is enabled
    #
    # @api private
    def synchronize(&block)
      if @thread_safe
        @mutex.synchronize(&block)
      else
        yield
      end
    end

    # Evict oldest entries if cache is at capacity
    #
    # @api private
    def evict_if_needed
      return if @data.size < @max_size

      # Find and remove the least recently used entry
      lru_key = @data.min_by { |_, v| v.accessed_at }&.first
      @data.delete(lru_key) if lru_key
    end

    # Remove expired entries
    #
    # @api private
    def cleanup_expired
      return unless @ttl

      @data.delete_if { |_, entry| entry.expired?(@ttl) }
    end
  end
end
