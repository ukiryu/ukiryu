# frozen_string_literal: true

module Ukiryu
  module Models
    # Information about how an executable was discovered
    #
    # Provides transparency about tool discovery - whether the executable
    # was found in PATH or is a shell alias, which shell was used,
    # and the alias definition if applicable.
    #
    # @example PATH discovery
    #   info = ExecutableInfo.new(
    #     path: "/usr/bin/ffmpeg",
    #     source: :path,
    #     shell: :bash
    #   )
    #
    # @example Alias discovery
    #   info = ExecutableInfo.new(
    #     path: "/usr/bin/ffmpeg",
    #     source: :alias,
    #     shell: :bash,
    #     alias_definition: "alias ffmpeg='/opt/homebrew/bin/ffmpeg'"
    #   )
    class ExecutableInfo
      # The full path to the executable
      #
      # @return [String] the executable path
      attr_reader :path

      # How the executable was discovered
      #
      # @return [Symbol] :path or :alias
      attr_reader :source

      # The shell used for discovery
      #
      # @return [Symbol] the shell (:bash, :zsh, :fish, :sh, etc.)
      attr_reader :shell

      # The alias definition if source is :alias
      #
      # @return [String, nil] the alias definition (e.g., "alias ffmpeg='...'")
      attr_reader :alias_definition

      def initialize(path:, source:, shell:, alias_definition: nil)
        @path = path
        @source = source
        @shell = shell
        @alias_definition = alias_definition
      end

      # Human-readable description
      #
      # @return [String] description of how executable was found
      def description
        case source
        when :path
          "Found in PATH at #{path}"
        when :alias
          "Shell alias in #{shell}: #{alias_definition}"
        end
      end

      # Check if this is a shell alias
      #
      # @return [Boolean] true if source is :alias
      def alias?
        source == :alias
      end

      # Check if this was found in PATH
      #
      # @return [Boolean] true if source is :path
      def path?
        source == :path
      end
    end
  end
end
