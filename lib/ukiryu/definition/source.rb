# frozen_string_literal: true

module Ukiryu
  module Definition
    # Abstract base class for definition sources
    #
    # A source represents a location from which a tool definition
    # can be loaded. Each source type (file, string, bundled, register)
    # implements this interface.
    #
    # @abstract Subclasses must implement {#load}, {#cache_key}, and {#source_type}
    class Source
      # Load the YAML definition content
      #
      # @abstract
      # @return [String] the YAML content
      # @raise [DefinitionLoadError] if the definition cannot be loaded
      def load
        raise NotImplementedError, "#{self.class} must implement #load"
      end

      # Get a unique cache key for this source
      #
      # The cache key must uniquely identify both the source location
      # and its content to ensure proper cache invalidation.
      #
      # @abstract
      # @return [String] a unique cache key
      def cache_key
        raise NotImplementedError, "#{self.class} must implement #cache_key"
      end

      # Get the source type identifier
      #
      # @abstract
      # @return [Symbol] the source type (:file, :string, :bundled, :register)
      def source_type
        raise NotImplementedError, "#{self.class} must implement #source_type"
      end

      # Check if this source is equal to another
      #
      # Two sources are equal if they have the same cache key.
      #
      # @param other [Object] the object to compare
      # @return [Boolean] true if sources are equal
      def ==(other)
        return false unless other.is_a?(Source)

        cache_key == other.cache_key
      end
      alias eql? ==

      # Generate hash code for hash storage
      #
      # @return [Integer] hash code based on cache key
      def hash
        cache_key.hash
      end

      # String representation
      #
      # @return [String] source description
      def to_s
        "#{source_type}:#{cache_key}"
      end

      # Inspect representation
      #
      # @return [String] detailed inspection string
      def inspect
        "#<#{self.class.name} source_type=#{source_type} cache_key=#{cache_key}>"
      end

      protected

      # Calculate SHA256 hash of a string
      #
      # @param string [String] the string to hash
      # @return [String] hexadecimal SHA256 hash
      def sha256(string)
        require 'digest'
        Digest::SHA256.hexdigest(string)
      end
    end
  end
end
