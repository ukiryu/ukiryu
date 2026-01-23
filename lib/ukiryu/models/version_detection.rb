# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Version detection configuration
    #
    # @example
    #   vd = VersionDetection.new(
    #     command: '--version',
    #     pattern: '(\d+\.\d+)',
    #     modern_threshold: '7.0'
    #   )
    class VersionDetection < Lutaml::Model::Serializable
      attribute :command, :string, collection: true, default: []
      attribute :pattern, :string
      attribute :modern_threshold, :string

      yaml do
        map_element 'command', to: :command
        map_element 'pattern', to: :pattern
        map_element 'modern_threshold', to: :modern_threshold
      end

      # Hash-like access for Base.detect_version compatibility
      #
      # @param key [Symbol, String] the attribute key
      # @return [Object] the attribute value
      def [](key)
        key_sym = key.to_sym
        # Return nil for unknown keys
        return nil unless respond_to?(key_sym, true)

        send(key_sym)
      end
    end
  end
end
