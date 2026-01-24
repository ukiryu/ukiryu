# frozen_string_literal: true

require_relative 'executor'

module Ukiryu
  # Version detector for external CLI tools
  #
  # This module provides centralized version detection logic with:
  # - Configurable version command patterns
  # - Regex pattern matching for version strings
  # - Proper shell handling for command execution
  # - Support for man-page based version detection (BSD/system tools)
  #
  # @example Detecting version from command output (GNU tools)
  #   version = VersionDetector.detect(
  #     executable: '/usr/bin/ffmpeg',
  #     command: '-version',
  #     pattern: /version (\d+\.\d+)/,
  #     shell: :bash
  #   )
  #
  # @example Detecting version from man page (BSD/system tools)
  #   version = VersionDetector.detect(
  #     executable: '/usr/bin/man',
  #     command: ['man', 'find'],
  #     pattern: /macOS ([\d.]+)/,
  #     source: 'man'
  #   )
  module VersionDetector
    class << self
      # Detect the version of an external tool
      #
      # @param executable [String] the executable path
      # @param command [String, Array<String>] the version command (default: '--version')
      # @param pattern [Regexp] the regex pattern to extract version
      # @param shell [Symbol] the shell to use for execution
      # @param source [String] the version source: 'command' (default) or 'man'
      # @return [String, nil] the detected version or nil if not found
      def detect(executable:, command: '--version', pattern: /(\d+\.\d+)/, shell: nil, source: 'command')
        # Return nil if executable is not found
        return nil if executable.nil? || executable.empty?

        shell ||= Shell.detect

        # Normalize command to array
        command_args = command.is_a?(Array) ? command : [command]

        result = Executor.execute(executable, command_args, shell: shell)

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
          return match[1] if match
        end

        match = stdout.match(pattern) || stderr.match(pattern)
        match[1] if match
      end
    end
  end
end
