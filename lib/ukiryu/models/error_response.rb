# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Error CLI execution response
    #
    # Contains error information when a command execution fails.
    class ErrorResponse < Lutaml::Model::Serializable
      attribute :status, :string, default: 'error'
      attribute :exit_code, :integer, default: 1
      attribute :error, :string

      yaml do
        map_element 'status', to: :status
        map_element 'exit_code', to: :exit_code
        map_element 'error', to: :error
      end

      json do
        map 'status', to: :status
        map 'exit_code', to: :exit_code
        map 'error', to: :error
      end

      # Create an ErrorResponse from an error message
      #
      # @param message [String] the error message
      # @param exit_code [Integer] the exit code (default: 1)
      # @return [ErrorResponse] the response model
      def self.from_message(message, exit_code: 1)
        new(
          status: 'error',
          exit_code: exit_code,
          error: message
        )
      end
    end
  end
end
