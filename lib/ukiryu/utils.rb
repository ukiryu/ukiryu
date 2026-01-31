# frozen_string_literal: true

module Ukiryu
  # Utils - Shared utility methods for Ukiryu
  #
  # Provides common utilities used throughout the codebase,
  # including hash transformation, file operations, and type coercion.
  #
  # == Usage
  #
  #   require 'ukiryu/utils'
  #
  #   # Symbolize hash keys recursively
  #   Ukiryu::Utils.symbolize_keys({ 'foo' => { 'bar' => 'baz' } })
  #   # => { foo: { bar: 'baz' } }
  #
  module Utils
    class << self
      # Recursively symbolize hash keys
      #
      # Converts all string keys to symbols, including nested hashes
      # and arrays containing hashes.
      #
      # @param hash [Hash] the hash to symbolize
      # @return [Hash] hash with symbolized keys
      #
      # @example
      #   Utils.symbolize_keys({ 'foo' => 'bar', 'nested' => { 'key' => 'value' } })
      #   # => { foo: 'bar', nested: { key: 'value' } }
      #
      def symbolize_keys(hash)
        hash.transform_keys { |k| k.to_s.to_sym }.transform_values do |value|
          case value
          when Hash
            symbolize_keys(value)
          when Array
            value.map { |v| v.is_a?(Hash) ? symbolize_keys(v) : v }
          else
            value
          end
        end
      end

      # Deep freeze a hash and all nested values
      #
      # Makes a hash immutable by freezing it and all nested structures.
      #
      # @param hash [Hash] the hash to freeze
      # @return [Hash] frozen hash
      #
      def deep_freeze(hash)
        hash.each do |key, value|
          if value.is_a?(Hash)
            deep_freeze(value)
          elsif value.is_a?(Array)
            value.each(&:freeze)
          end
          key.freeze
        end
        hash.freeze
      end

      # Safely require a file, caching the result
      #
      # @param path [String] the file path to require
      # @return [Boolean] true if loaded, false if already loaded
      #
      def safe_require(path)
        require path
        true
      rescue LoadError => e
        raise e
      rescue RuntimeError
        # Already loaded
        false
      end

      # Coerce a value to a specific type
      #
      # @param value [Object] the value to coerce
      # @param type [Symbol] the target type (:string, :integer, :float, :boolean, :symbol, :array)
      # @return [Object] the coerced value
      #
      # @example
      #   Utils.coerce('42', :integer)  # => 42
      #   Utils.coerce('true', :boolean) # => true
      #
      def coerce(value, type)
        return value if value.is_a?(type) && type != :array

        case type
        when :string
          value.to_s
        when :integer
          value.to_i
        when :float
          value.to_f
        when :boolean
          coerce_boolean(value)
        when :symbol
          value.to_s.to_sym
        when :array
          Array(value)
        else
          value
        end
      end

      # Escape a string for shell usage
      #
      # @param str [String] the string to escape
      # @param shell [Symbol] the shell type (:unix, :windows, :powershell)
      # @return [String] escaped string
      #
      def shell_escape(str, shell = :unix)
        case shell
        when :unix
          str.to_s.inspect
        when :powershell
          "'#{str.to_s.gsub("'", "''")}'"
        when :windows
          str.to_s.gsub('"', '^^"')
        else
          str.to_s
        end
      end

      # Format a path for the current shell
      #
      # @param path [String] the path to format
      # @param shell [Symbol] the shell type
      # @return [String] formatted path
      #
      def format_path(path, shell = :unix)
        path = path.to_s
        case shell
        when :unix
          path.gsub('\\', '/')
        when :windows
          path.gsub('/', '\\')
        else
          path
        end
      end

      # Generate a cache key from arguments
      #
      # Creates a deterministic string key from various input types.
      #
      # @param args [Array] the arguments to create key from
      # @return [String] cache key string
      #
      def cache_key(*args)
        args.map do |arg|
          case arg
          when nil
            'nil'
          when true
            'true'
          when false
            'false'
          when Array
            "[#{arg.map { |a| cache_key(a) }.join(',')}]"
          when Hash
            "{#{arg.map { |k, v| "#{cache_key(k)}:#{cache_key(v)}" }.join(',')}}"
          when Symbol
            ":#{arg}"
          when String
            arg.include?(' ') || arg.include?(':') ? arg.inspect : arg
          else
            arg.to_s
          end
        end.join(':')
      end

      # Memoize a method with a thread-safe cache
      #
      # @param key_prefix [String] the cache key prefix
      # @param expiry [Integer] optional expiry in seconds
      # @return [Object] the memoized result
      #
      def memoize(key_prefix, expiry = nil)
        cache = @memo_cache ||= {}
        cache_key = expiry ? "#{key_prefix}:#{Time.now.to_i / expiry}" : key_prefix

        return cache[cache_key] if cache.key?(cache_key)

        result = yield
        cache[cache_key] = result
        result
      end

      # Clear the memoization cache
      #
      def clear_memo_cache
        @memo_cache = nil
      end

      private

      # Coerce to boolean handling various string representations
      #
      def coerce_boolean(value)
        case value
        when true, 'true', '1', 'yes', 'on'
          true
        when false, 'false', '0', 'no', 'off', nil
          false
        else
          !value.nil?
        end
      end
    end
  end
end
