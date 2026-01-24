# frozen_string_literal: true

module Ukiryu
  module Definition
    # Resolve semantic version constraints
    #
    # This class handles semantic versioning constraints like:
    # - "1.0" - exact version
    # - ">= 1.0" - minimum version (inclusive)
    # - "~> 1.2" - pessimistic version constraint
    class VersionResolver
      # Version constraint structure
      class Constraint
        attr_reader :operator, :version, :raw

        def initialize(operator, version, raw = nil)
          @operator = operator
          @version = version
          @raw = raw || "#{operator} #{version}"
        end

        # Exact version constraint
        def self.exact(version)
          new(:==, version, version)
        end

        # Minimum version constraint (inclusive)
        def self.min(version)
          new(:>=, version)
        end

        # Maximum version constraint (inclusive)
        def self.max(version)
          new(:<=, version)
        end

        # Pessimistic version constraint
        def self.pessimistic(version)
          new('~>'.to_sym, version)
        end

        # Range constraint
        def self.range(min_version, max_version)
          # This is represented as two constraints internally
          [new(:>=, min_version), new(:<, max_version)]
        end

        def to_s
          @raw
        end
      end

      # Parse a version constraint string
      #
      # @param constraint_string [String] the constraint string
      # @return [Array<Constraint>] array of constraints
      def self.parse_constraint(constraint_string)
        return [Constraint.exact(constraint_string)] unless constraint_string.match?(/[<>=~]/)

        constraints = []

        # Split by comma for compound constraints
        constraint_string.split(',').map(&:strip).each do |part|
          case part
          when /\A~>(?:\s*(.+))?/ # Updated regex for ~> operator
            # Pessimistic version constraint
            version = ::Regexp.last_match(1) || ''
            constraints << Constraint.pessimistic(version.strip)
          when /\A>=\s*(.+)/
            # Minimum version (inclusive)
            constraints << Constraint.min(::Regexp.last_match(1))
          when /\A>\s*(.+)/
            # Minimum version (exclusive)
            constraints << Constraint.new(:>, ::Regexp.last_match(1))
          when /\A<=\s*(.+)/
            # Maximum version (inclusive)
            constraints << Constraint.max(::Regexp.last_match(1))
          when /\A<\s*(.+)/
            # Maximum version (exclusive)
            constraints << Constraint.new(:<, ::Regexp.last_match(1))
          when /\A==\s*(.+)/
            # Exact version
            constraints << Constraint.exact(::Regexp.last_match(1))
          else
            # Assume exact version
            constraints << Constraint.exact(part.strip)
          end
        end

        constraints
      end

      # Check if a version satisfies a constraint
      #
      # @param version [String] the version to check
      # @param constraint [String, Array<Constraint>] the constraint(s)
      # @return [Boolean] true if version satisfies constraint
      def self.satisfies?(version, constraint)
        constraints = constraint.is_a?(Array) ? constraint : parse_constraint(constraint)

        v_parts = parse_version(version)

        constraints.all? do |c|
          case c.operator
          when :==
            v_parts == parse_version(c.version)
          when :>=
            compare_versions(v_parts, parse_version(c.version)) >= 0
          when :>
            compare_versions(v_parts, parse_version(c.version)).positive?
          when :<=
            compare_versions(v_parts, parse_version(c.version)) <= 0
          when :<
            compare_versions(v_parts, parse_version(c.version)).negative?
          when '~>'.to_sym
            # Pessimistic version constraint: >= x.y.z, < x.(y+1).0
            base = parse_version(c.version)
            upper = base[0...-1] + [base[-1] + 1, 0]
            compare_versions(v_parts, base) >= 0 && compare_versions(v_parts, upper).negative?
          else
            false
          end
        end
      end

      # Resolve the best matching version from available versions
      #
      # @param constraint [String] the version constraint
      # @param available_versions [Array<String>] available versions
      # @return [String, nil] best matching version, or nil if none match
      def self.resolve(constraint, available_versions)
        return nil if available_versions.nil? || available_versions.empty?

        # Parse constraint
        constraints = parse_constraint(constraint)

        # Filter versions that satisfy the constraint
        matching = available_versions.select { |v| satisfies?(v, constraints) }

        # Return highest matching version
        matching.max_by { |v| parse_version(v) }
      end

      # Compare two version strings
      #
      # @param v1 [String, Array] first version or parts
      # @param v2 [String, Array] second version or parts
      # @return [Integer] comparison result (-1, 0, 1)
      def self.compare_versions(v1, v2)
        parts1 = v1.is_a?(Array) ? v1 : parse_version(v1)
        parts2 = v2.is_a?(Array) ? v2 : parse_version(v2)

        max_length = [parts1.length, parts2.length].max
        max_length.times do |i|
          p1 = parts1[i] || 0
          p2 = parts2[i] || 0
          comparison = p1 <=> p2
          return comparison unless comparison.zero?
        end

        0
      end

      # Parse a version string into components
      #
      # @param version_string [String] the version string
      # @return [Array<Integer>] version components
      def self.parse_version(version_string)
        version_string.to_s.split('.').map(&:to_i)
      end

      # Get the latest version from a list
      #
      # @param versions [Array<String>] list of versions
      # @return [String, nil] the latest version
      def self.latest(versions)
        return nil if versions.nil? || versions.empty?

        versions.max_by { |v| parse_version(v) }
      end

      # Get the compatible version range for a pessimistic constraint
      #
      # @param version [String] the base version
      # @return [Array<String>] [min_version, max_version]
      def self.pessimistic_range(version)
        parts = parse_version(version)
        min = version
        max = "#{parts[0...-1].join('.')}.#{parts[-1] + 1}"
        [min, max]
      end
    end
  end
end
