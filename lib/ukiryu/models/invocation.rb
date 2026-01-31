# frozen_string_literal: true

module Ukiryu
  module Models
    # Invocation configuration for tool commands
    #
    # Defines how a tool is invoked - whether as a direct executable
    # or with subcommands, and whether it provides multiple tools.
    #
    # @example Direct invocation
    #   invocation = Invocation.new(type: 'direct')
    #
    # @example Subcommand invocation (ImageMagick 7.x)
    #   invocation = Invocation.new(
    #     type: 'subcommand',
    #     multi_call: true
    #   )
    #
    # @example Multi-call binary (BusyBox)
    #   invocation = Invocation.new(
    #     type: 'subcommand',
    #     multi_call: true,
    #     symlink_detection: true
    #   )
    class Invocation < Lutaml::Model::Serializable
      # Invocation type: direct or subcommand
      #
      # - direct: The executable IS the command (e.g., `convert input.png output.jpg`)
      # - subcommand: Command is a subcommand of executable (e.g., `magick convert input.png output.jpg`)
      attribute :type, :string

      # Does this executable provide multiple tools?
      #
      # Examples:
      # - BusyBox: true (provides ls, cat, gzip, etc.)
      # - ImageMagick 7.x magick: true (provides convert, identify, mogrify)
      # - ImageMagick 6.x convert: false (only provides convert)
      attribute :multi_call, :boolean, default: false

      # Should discovery check for symlinks to this executable?
      #
      # Used for multi-call binaries like BusyBox where tools are accessed
      # via symlinks (e.g., /bin/gzip → /bin/busybox).
      attribute :symlink_detection, :boolean, default: false

      key_value do
        map 'type', to: :type
        map 'multi_call', to: :multi_call
        map 'symlink_detection', to: :symlink_detection
      end

      # Check if this is a direct invocation
      #
      # @return [Boolean] true if type is 'direct'
      def direct?
        type == 'direct'
      end

      # Check if this is a subcommand invocation
      #
      # @return [Boolean] true if type is 'subcommand'
      def subcommand?
        type == 'subcommand'
      end

      # Check if this is a multi-call binary
      #
      # @return [Boolean] true if multi_call is true
      def multi_call?
        multi_call == true
      end
    end
  end
end
