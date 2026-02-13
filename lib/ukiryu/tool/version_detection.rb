# frozen_string_literal: true

module Ukiryu
  class Tool
    # Version detection and compatibility checking
    #
    # Provides methods to detect tool versions using various strategies:
    # - Command-line flags (e.g., --version)
    # - Man page parsing
    # - Profile-defined version
    #
    # Also includes version compatibility checking with profile requirements
    # and feature flag probing.
    #
    # @api private
    module VersionDetection
      # Detect tool version using VersionDetector
      #
      # Supports both legacy format (command/pattern) and new methods array.
      # The methods array allows fallback hierarchy: try command first,
      # then man page, etc.
      #
      # @return [Models::VersionInfo, nil] the version info or nil if not detected
      def detect_version
        vd = @profile.version_detection
        return nil unless vd

        # Check for new detection_methods array format
        return detect_version_with_detection_methods(vd.detection_methods) if vd.respond_to?(:detection_methods) && vd.detection_methods && !vd.detection_methods.empty?

        # Legacy format: command-based detection
        return nil if vd.command.nil? || vd.command.empty?

        # If pattern is empty, skip version detection and use hardcoded version from profile
        # This is useful for tools like BusyBox applets that don't have their own --version flag
        if vd.pattern.nil? || (vd.pattern.respond_to?(:empty?) && vd.pattern.empty?)
          return Models::VersionInfo.new(
            value: @profile.version,
            method_used: :profile,
            available_methods: [:profile]
          )
        end

        # For man page detection, the executable is 'man' and command is the tool name
        # For command detection, the executable is the tool itself
        source = vd.respond_to?(:source) ? vd.source : 'command'
        if source == 'man'
          # command is ['man', 'tool_name'], so:
          # - executable = 'man'
          # - command = ['tool_name']  (just the tool name for man)
          executable = 'man'
          command_args = vd.command[1..] # Skip 'man', use rest of array
        else
          executable = @executable
          command_args = vd.command
        end

        Ukiryu::VersionDetector.detect_info(
          executable: executable,
          command: command_args,
          pattern: vd.pattern || /(\d+\.\d+)/,
          shell: @shell,
          source: source,
          timeout: 30 # Internal operation: hardcoded timeout
        )
      end

      # Detect version using detection_methods array with fallback hierarchy
      #
      # @param detection_methods [Array] array of method definitions from YAML
      # @return [Models::VersionInfo, nil] version info or nil
      def detect_version_with_detection_methods(detection_methods)
        # Convert YAML detection_methods to format expected by VersionDetector
        detector_methods = detection_methods.map do |m|
          # Handle both Hash and Lutaml::Model objects
          type = if m.respond_to?(:type)
                   m.type
                 elsif m.is_a?(Hash)
                   m[:type] || m['type']
                 end

          if [:man_page, 'man_page'].include?(type)
            paths = if m.respond_to?(:paths)
                      m.paths
                    elsif m.is_a?(Hash)
                      m[:paths] || m['paths']
                    else
                      {}
                    end

            {
              type: :man_page,
              paths: paths
            }
          else
            command = if m.respond_to?(:command)
                        m.command
                      elsif m.is_a?(Hash)
                        m[:command] || m['command']
                      end

            pattern = if m.respond_to?(:pattern)
                        m.pattern
                      elsif m.is_a?(Hash)
                        m[:pattern] || m['pattern']
                      end

            {
              type: :command,
              command: command || '--version',
              pattern: pattern || /(\d+\.\d+)/
            }
          end
        end

        Ukiryu::VersionDetector.detect_with_methods(
          executable: @executable,
          methods: detector_methods,
          shell: @shell,
          timeout: 30 # Default timeout for version detection
        )
      end

      # Check version compatibility with profile requirements
      #
      # @param mode [Symbol] check mode (:strict, :lenient, :probe)
      # @return [VersionCompatibility] the compatibility result
      def check_version_compatibility(mode = :strict)
        installed = version
        requirement = profile_version_requirement

        # If no requirement, always compatible
        if !requirement || requirement.empty?
          return Ukiryu::VersionCompatibility.new(
            installed_version: installed || 'unknown',
            required_version: 'none',
            compatible: true,
            reason: nil
          )
        end

        # If installed version unknown, probe for it
        installed = detect_version&.to_s if !installed && mode == :probe

        # If still unknown, handle based on mode
        unless installed
          if mode == :strict
            return Ukiryu::VersionCompatibility.new(
              installed_version: 'unknown',
              required_version: requirement,
              compatible: false,
              reason: 'Cannot determine installed tool version'
            )
          else
            return Ukiryu::VersionCompatibility.new(
              installed_version: 'unknown',
              required_version: requirement,
              compatible: true,
              reason: 'Warning: Could not verify version compatibility'
            )
          end
        end

        # Check compatibility
        result = Ukiryu::VersionCompatibility.check(installed, requirement)

        if !result.compatible? && mode == :lenient
          # In lenient mode, return compatible but with warning
          return VersionCompatibility.new(
            installed_version: installed,
            required_version: requirement,
            compatible: true,
            reason: "Warning: #{result.reason}"
          )
        end

        result
      end

      # Probe for a feature flag
      #
      # Tests if the tool supports a specific feature by checking
      # for a command-line flag.
      #
      # @param flag [String] the feature flag to probe (e.g., '--worktree')
      # @return [Boolean] true if the feature is supported
      def probe_flag(flag)
        return false unless @executable

        result = Executor.execute(
          @executable,
          [flag, '--help'],
          shell: @shell,
          timeout: 5
        )

        # Some tools exit 0 even for unknown flags, check stderr
        # If the flag is valid, --help should show info about it
        result.success? && !result.stderr.include?('unknown')
      end

      # Get version requirement from compatible profile
      #
      # @return [String, nil] the version requirement
      def profile_version_requirement
        @command_profile&.version_requirement
      end
    end
  end
end
