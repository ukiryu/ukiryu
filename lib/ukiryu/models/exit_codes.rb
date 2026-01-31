# frozen_string_literal: true

module Ukiryu
  module Models
    # Exit code definitions for tool commands
    #
    # Provides machine-readable error semantics for exit codes.
    #
    # @example
    #   exit_codes = ExitCodes.new(
    #     standard: { '0' => 'success', '1' => 'general_error' },
    #     custom: { '3' => 'merge_conflict', '4' => 'permission_denied' }
    #   )
    class ExitCodes < Lutaml::Model::Serializable
      attribute :standard, :hash, default: {}
      attribute :custom, :hash, default: {}

      key_value do
        map 'standard', to: :standard
        map 'custom', to: :custom
      end

      # Get the meaning of an exit code
      #
      # @param code [Integer] the exit code
      # @return [String, nil] the meaning or nil if not defined
      def meaning(code)
        code_str = code.to_s

        # Check custom codes first (more specific)
        @custom&.dig(code_str) || @standard&.dig(code_str)
      end

      # Check if an exit code is defined
      #
      # @param code [Integer] the exit code
      # @return [Boolean] true if defined
      def defined?(code)
        !meaning(code).nil?
      end

      # Check if an exit code indicates success
      #
      # @param code [Integer] the exit code
      # @return [Boolean] true if success (0 or defined as success)
      def success?(code)
        code.zero? || meaning(code) == 'success'
      end

      # Get all defined exit codes
      #
      # @return [Hash] all codes merged (standard + custom)
      def all_codes
        @standard.to_h.merge(@custom.to_h)
      end

      # Get standard exit codes
      #
      # @return [Hash] standard codes
      def standard_codes
        @standard.to_h
      end

      # Get custom exit codes
      #
      # @return [Hash] custom codes
      def custom_codes
        @custom.to_h
      end
    end
  end
end
