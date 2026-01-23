# frozen_string_literal: true

module Ukiryu
  # Version compatibility model
  #
  # Checks if an installed tool version is compatible with
  # the version requirements specified in a tool profile.
  class VersionCompatibility
    attr_reader :installed_version, :required_version, :compatible, :reason

    # Initialize version compatibility check
    #
    # @param installed_version [String] the installed tool version
    # @param required_version [String] the version requirement (e.g., ">= 2.30")
    # @param compatible [Boolean] whether the versions are compatible
    # @param reason [String, nil] the reason for incompatibility
    def initialize(installed_version:, required_version:, compatible:, reason: nil)
      @installed_version = installed_version
      @required_version = required_version
      @compatible = compatible
      @reason = reason
    end

    # Check if versions are compatible
    #
    # @return [Boolean] true if compatible
    def compatible?
      @compatible
    end

    # Check if versions are incompatible
    #
    # @return [Boolean] true if incompatible
    def incompatible?
      !@compatible
    end

    # Get a human-readable status message
    #
    # @return [String] the status message
    def status_message
      if @compatible
        "Version #{@installed_version} is compatible with requirement #{@required_version}"
      else
        @reason || "Version #{@installed_version} is not compatible with requirement #{@required_version}"
      end
    end

    # Check compatibility against a version requirement
    #
    # @param installed_version [String] the installed version
    # @param requirement [String] the version requirement (e.g., ">= 2.30")
    # @return [VersionCompatibility] the compatibility result
    def self.check(installed_version, requirement)
      return new(installed_version: installed_version, required_version: requirement, compatible: true, reason: nil) if !requirement || requirement.empty?

      parser = RequirementParser.new(requirement)
      compatible = parser.satisfied_by?(installed_version)

      if compatible
        new(installed_version: installed_version, required_version: requirement, compatible: true, reason: nil)
      else
        new(installed_version: installed_version, required_version: requirement, compatible: false,
            reason: "Version #{installed_version} does not satisfy requirement: #{requirement}")
      end
    end

    # Requirement parser for semantic versioning
    class RequirementParser
      # Parse a version requirement
      #
      # @param requirement [String] the requirement string (e.g., ">= 2.30, < 3.0")
      def initialize(requirement)
        @requirement = requirement
        @constraints = parse_requirements
      end

      # Check if a version satisfies the requirements
      #
      # @param version [String] the version to check
      # @return [Boolean] true if satisfied
      def satisfied_by?(version)
        return true if @constraints.empty?

        @constraints.all? { |constraint| satisfied?(version, constraint) }
      end

      private

      # Parse requirement string into constraint array
      #
      # @return [Array<Hash>] array of constraint hashes
      def parse_requirements
        @requirement.split(',').map(&:strip).map do |req|
          if req =~ /^([><=!~]+)\s*(.+)/
            { operator: Regexp.last_match(1), version: Regexp.last_match(2) }
          else
            # Default to equality
            { operator: '==', version: req }
          end
        end
      end

      # Check if a version satisfies a single constraint
      #
      # @param version [String] the version to check
      # @param constraint [Hash] the constraint hash
      # @return [Boolean] true if satisfied
      def satisfied?(version, constraint)
        v = parse_version(version)
        req_v = parse_version(constraint[:version])

        case constraint[:operator]
        when '>', '>='
          compare_versions(v, req_v) > 0 || (constraint[:operator] == '>=' && v == req_v)
        when '<', '<='
          compare_versions(v, req_v) < 0 || (constraint[:operator] == '<=' && v == req_v)
        when '==', '='
          v == req_v
        when '!='
          v != req_v
        when '~>'
          # Optimistic operator (~> 2.5 means >= 2.5 and < 3.0)
          compare_versions(v, req_v) >= 0 && (v[0] == req_v[0])
        else
          false
        end
      end

      # Parse version string into array of integers
      #
      # @param version [String] the version string
      # @return [Array<Integer>] the version components
      def parse_version(version)
        version.split('.').map(&:to_i)
      end

      # Compare two version arrays
      #
      # @param v1 [Array<Integer>] first version
      # @param v2 [Array<Integer>] second version
      # @return [Integer] -1, 0, or 1
      def compare_versions(v1, v2)
        max_length = [v1.length, v2.length].max
        v1_padded = v1 + [0] * (max_length - v1.length)
        v2_padded = v2 + [0] * (max_length - v2.length)

        v1_padded <=> v2_padded
      end
    end
  end
end
