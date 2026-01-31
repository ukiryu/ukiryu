# frozen_string_literal: true

module Ukiryu
  # Version detector for external CLI tools
  #
  # This module provides centralized version detection logic with:
  # - Configurable version command patterns
  # - Regex pattern matching for version strings
  # - Proper shell handling for command execution
  # - Support for man-page based version detection (BSD/system tools)
  # - Fallback hierarchy: try multiple methods, use first success
  #
  # @example Detecting version from command output (GNU tools)
  #   info = VersionDetector.detect(
  #     executable: '/usr/bin/ffmpeg',
  #     command: '-version',
  #     pattern: /version (\d+\.\d+)/,
  #     shell: :bash
  #   )
  #
  # @example Detecting version with fallback hierarchy
  #   info = VersionDetector.detect_with_methods(
  #     executable: '/usr/bin/xargs',
  #     methods: [
  #       { type: :command, command: '--version', pattern: /xargs \(GNU findutils\) ([\d.]+)/ },
  #       { type: :man_page, paths: { macos: '/usr/share/man/man1/xargs.1' } }
  #     ],
  #     shell: :bash
  #   )
  module VersionDetector
    class << self
      # Detect the version of an external tool (legacy API)
      #
      # @param executable [String] the executable path
      # @param command [String, Array<String>] the version command (default: '--version')
      # @param pattern [Regexp] the regex pattern to extract version
      # @param shell [Symbol] the shell to use for execution
      # @param source [String] the version source: 'command' (default) or 'man'
      # @param timeout [Integer] timeout in seconds (default: 30)
      # @return [String, nil] the detected version or nil if not found
      def detect(executable:, command: '--version', pattern: /(\d+\.\d+)/, shell: nil, source: 'command', timeout: 30)
        result = detect_info(
          executable: executable,
          command: command,
          pattern: pattern,
          shell: shell,
          source: source,
          timeout: timeout
        )

        result&.value
      end

      # Detect version with full info (VersionInfo)
      #
      # @param executable [String] the executable path
      # @param command [String, Array<String>] the version command (default: '--version')
      # @param pattern [Regexp] the regex pattern to extract version
      # @param shell [Symbol] the shell to use for execution
      # @param source [String] the version source: 'command' (default) or 'man'
      # @param timeout [Integer] timeout in seconds (default: 30 for version detection)
      # @return [VersionInfo, nil] the version info or nil if not found
      def detect_info(executable:, command: '--version', pattern: /(\d+\.\d+)/, shell: nil, source: 'command',
                      timeout: 30)
        # Return nil if executable is not found
        return nil if executable.nil? || executable.empty?

        shell ||= Ukiryu::Shell.detect

        # Normalize command to array
        command_args = command.is_a?(Array) ? command : [command]

        # DEBUG: Log timing to investigate timeout issues
        start_time = Time.now
        result = Ukiryu::Executor.execute(executable, command_args, shell: shell, allow_failure: true, timeout: timeout)
        elapsed = Time.now - start_time
        warn "[UKIRYU DEBUG] Version detection for #{File.basename(executable)} took #{elapsed.round(2)}s (expected <0.1s)" if elapsed > 1

        return nil unless result.success?

        # Sanitize strings to handle invalid UTF-8 sequences
        stdout = result.stdout.scrub
        stderr = result.stderr.scrub

        # For man pages, look at the tail (last few lines)
        if source == 'man'
          output = stdout + stderr
          # Get last 500 characters to catch the OS version at bottom
          tail = output[-500..] || output
          match = tail.match(pattern)
          if match
            return Models::VersionInfo.new(
              value: match[1],
              method_used: :man_page,
              available_methods: [:man_page]
            )
          end
        end

        match = stdout.match(pattern) || stderr.match(pattern)

        return nil unless match

        Models::VersionInfo.new(
          value: match[1],
          method_used: :command,
          available_methods: [:command]
        )
      rescue StandardError
        # Return nil on any error (command not found, execution error, etc.)
        nil
      end

      # Detect version using multiple methods with fallback hierarchy
      #
      # Tries each method in order and returns the first successful result.
      # Methods are NOT mutually exclusive - they work together as fallbacks.
      #
      # @param executable [String] the tool executable path
      # @param methods [Array<Hash>] array of method definitions
      # @param shell [Symbol] the shell to use
      # @param timeout [Integer] timeout in seconds (default: 30)
      # @return [VersionInfo, nil] version info or nil if all methods fail
      def detect_with_methods(executable:, methods:, shell: nil, timeout: 30)
        shell ||= Ukiryu::Shell.detect

        # Track available methods for VersionInfo
        available_methods = methods.map { |m| m[:type] }.uniq

        # Try each method in order
        methods.each do |method|
          case method[:type]
          when :command
            # Try command-based detection
            info = detect_info(
              executable: executable,
              command: method[:command] || '--version',
              pattern: method[:pattern] || /(\d+\.\d+)/,
              shell: shell,
              source: 'command',
              timeout: timeout
            )

            return info if info

          when :man_page
            # Try man page date extraction
            paths = method[:paths] || {}

            # Resolve man page path for current platform
            platform = Ukiryu::Platform.detect
            man_path = paths[platform] || paths[platform.to_s]

            next unless man_path

            # Parse date from man page
            date_str = Ukiryu::ManPageParser.parse_date(man_path)

            next unless date_str

            return Models::VersionInfo.new(
              value: date_str,
              method_used: :man_page,
              available_methods: available_methods
            )
          end
        end

        # All methods failed
        nil
      end
    end
  end
end
