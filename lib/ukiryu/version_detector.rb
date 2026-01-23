# frozen_string_literal: true

require_relative 'executor'

module Ukiryu
  # Version detector for external CLI tools
  #
  # This module provides centralized version detection logic with:
  # - Configurable version command patterns
  # - Regex pattern matching for version strings
  # - Proper shell handling for command execution
  #
  # @example Detecting version
  #   version = VersionDetector.detect(
  #     executable: '/usr/bin/ffmpeg',
  #     command: '-version',
  #     pattern: /version (\d+\.\d+)/,
  #     shell: :bash
  #   )
  module VersionDetector
    class << self
      # Detect the version of an external tool
      #
      # @param executable [String] the executable path
      # @param command [String, Array<String>] the version command (default: '--version')
      # @param pattern [Regexp] the regex pattern to extract version
      # @param shell [Symbol] the shell to use for execution
      # @return [String, nil] the detected version or nil if not found
      def detect(executable:, command: '--version', pattern: /(\d+\.\d+)/, shell: nil)
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

        match = stdout.match(pattern) || stderr.match(pattern)
        match[1] if match
      end
    end
  end
end
