# frozen_string_literal: true

module Ukiryu
  module Models
    # Semantic version value object for proper version comparison.
    #
    # Handles version strings like "10.0", "9.5.1", "1.2.3" and provides
    # proper semantic comparison (10.0 > 9.5, not alphabetical).
    #
    # This class ensures that version selection uses actual semantic meaning
    # rather than string comparison, which would incorrectly sort "9.5" > "10.0".
    #
    # @example
    #   v1 = Ukiryu::Models::SemanticVersion.new("10.0")
    #   v2 = Ukiryu::Models::SemanticVersion.new("9.5")
    #   v1 > v2  # => true (correct)
    #   "10.0" > "9.5"  # => false (wrong - alphabetical)
    #
    class SemanticVersion
      include Comparable

      # Parse a version string into segments
      #
      # @param version_string [String, nil] the version string to parse
      # @return [Array<Integer>] array of numeric segments
      def self.parse(version_string)
        return [0] if version_string.nil? || version_string.to_s.empty?

        version_string.to_s
                      .split('.')
                      .map do |part|
                        part.to_i
        rescue StandardError
          0
        end
      end

      # Compare two version strings directly
      #
      # @param version_a [String] first version string
      # @param version_b [String] second version string
      # @return [Integer] -1, 0, or 1
      def self.compare(version_a, version_b)
        segments1 = parse(version_a)
        segments2 = parse(version_b)

        max_length = [segments1.length, segments2.length].max
        padded1 = segments1 + [0] * (max_length - segments1.length)
        padded2 = segments2 + [0] * (max_length - segments2.length)

        padded1 <=> padded2
      end

      # @return [Array<Integer>] the numeric segments of this version
      attr_reader :segments

      # @return [String, nil] the original version string
      attr_reader :original

      # Create a new SemanticVersion from a version string
      #
      # @param version_string [String, Integer, SemanticVersion, nil] the version
      def initialize(version_string)
        @original = version_string.respond_to?(:to_s) ? version_string.to_s : nil
        @segments = self.class.parse(@original)
      end

      # Compare this version with another
      #
      # @param other [SemanticVersion, String, Integer, nil] the other version
      # @return [Integer, nil] -1, 0, 1, or nil if not comparable
      def <=>(other)
        return nil unless other

        other_segments = case other
                         when SemanticVersion
                           other.segments
                         when String, Integer
                           self.class.parse(other)
                         else
                           return nil
                         end

        # Compare segment by segment
        # [10, 0] <=> [9, 5] should return 1 (10.0 > 9.5)
        max_length = [segments.length, other_segments.length].max

        max_length.times do |i|
          a = segments[i] || 0
          b = other_segments[i] || 0

          return a <=> b unless a == b
        end

        0 # All segments equal
      end

      # Check equality with another version
      #
      # @param other [Object] the other object
      # @return [Boolean]
      def ==(other)
        return false unless other

        (self <=> other).zero?
      end

      # Check if this version is greater than another
      #
      # @param other [SemanticVersion, String, Integer, nil] the other version
      # @return [Boolean]
      def >(other)
        (self <=> other) == 1
      end

      # Check if this version is less than another
      #
      # @param other [SemanticVersion, String, Integer, nil] the other version
      # @return [Boolean]
      def <(other)
        (self <=> other) == -1
      end

      # Check if this version is greater than or equal to another
      #
      # @param other [SemanticVersion, String, Integer, nil] the other version
      # @return [Boolean]
      def >=(other)
        result = self <=> other
        [1, 0].include?(result)
      end

      # Check if this version is less than or equal to another
      #
      # @param other [SemanticVersion, String, Integer, nil] the other version
      # @return [Boolean]
      def <=(other)
        result = self <=> other
        [-1, 0].include?(result)
      end

      # Return the version as a string
      #
      # @return [String] the version string
      def to_s
        segments.join('.')
      end

      # Return a human-readable representation
      #
      # @return [String]
      def inspect
        "#<Ukiryu::Models::SemanticVersion #{self}>"
      end

      # Hash for use as hash key
      #
      # @return [Integer]
      def hash
        segments.hash
      end

      # Equality for hash key usage
      #
      # @param other [Object]
      # @return [Boolean]
      def eql?(other)
        return false unless other.is_a?(SemanticVersion)

        segments == other.segments
      end
    end
  end
end
