# frozen_string_literal: true

module Ukiryu
  module Definition
    # Metadata about a discovered tool definition
    #
    # This class encapsulates information about a tool definition
    # that was discovered in the filesystem.
    class DefinitionMetadata
      include Comparable

      # The tool name
      # @return [String] tool name
      attr_reader :name

      # The tool version
      # @return [String] tool version
      attr_reader :version

      # The path to the definition file
      # @return [String] absolute path to the YAML file
      attr_reader :path

      # The source type (user, system, bundled, register)
      # @return [Symbol] source type
      attr_reader :source_type

      # Create a new definition metadata
      #
      # @param name [String] tool name
      # @param version [String] tool version
      # @param path [String] path to the definition file
      # @param source_type [Symbol] source type
      def initialize(name:, version:, path:, source_type:)
        @name = name
        @version = version
        @path = File.expand_path(path)
        @source_type = source_type
      end

      # Get the tool definition by loading the YAML
      #
      # @return [Models::ToolDefinition] the loaded tool definition
      # @raise [DefinitionLoadError] if loading fails
      def load_definition
        Loader.load_from_file(@path)
      end

      # Check if the definition file exists
      #
      # @return [Boolean] true if file exists
      def exists?
        File.exist?(@path)
      end

      # Get the file modification time
      #
      # @return [Time, nil] file mtime, or nil if file doesn't exist
      def mtime
        File.mtime(@path) if exists?
      end

      # Get a string representation
      #
      # @return [String] string representation
      def to_s
        "#{@name}/#{@version} (#{@source_type}) - #{@path}"
      end

      # Detailed inspection string
      #
      # @return [String] inspection string
      def inspect
        "#<#{self.class.name} name=#{@name.inspect} version=#{@version.inspect} path=#{@path.inspect} source_type=#{@source_type.inspect}>"
      end

      # Compare two metadata objects
      #
      # @param other [DefinitionMetadata] the other metadata
      # @return [Boolean] true if equal
      def ==(other)
        return false unless other.is_a?(DefinitionMetadata)

        @name == other.name &&
          @version == other.version &&
          @path == other.path &&
          @source_type == other.source_type
      end

      # Hash code for hash keys
      #
      # @return [Integer] hash code
      def hash
        [@name, @version, @path, @source_type].hash
      end

      # Source type priorities (lower = higher priority)
      #
      # @return [Integer] priority value
      def priority
        case @source_type
        when :user then 1
        when :bundled then 2
        when :local_system then 3
        when :system then 4
        when :register then 5
        else 999
        end
      end

      # Compare priorities for sorting
      #
      # @param other [DefinitionMetadata] the other metadata
      # @return [Integer] comparison result
      def <=>(other)
        return 0 unless other.is_a?(DefinitionMetadata)

        # Compare by priority (lower number = higher priority)
        priority_comparison = priority <=> other.priority
        return priority_comparison unless priority_comparison.zero?

        # Same priority, compare by version (descending - higher version first)
        version_comparison = compare_versions(@version, other.version)
        return version_comparison unless version_comparison.zero?

        # Same version, compare by name
        @name <=> other.name
      end

      private

      # Compare version strings
      #
      # Returns result for descending order (higher version first)
      #
      # @param v1 [String] first version
      # @param v2 [String] second version
      # @return [Integer] comparison result (negated for descending)
      def compare_versions(v1, v2)
        # Simple version comparison - can be enhanced later
        parts1 = v1.split('.').map(&:to_i)
        parts2 = v2.split('.').map(&:to_i)

        max_length = [parts1.length, parts2.length].max
        max_length.times do |i|
          p1 = parts1[i] || 0
          p2 = parts2[i] || 0
          comparison = p1 <=> p2
          # Negate for descending order (higher version = lower value)
          return -comparison unless comparison.zero?
        end

        0
      end
    end
  end
end
