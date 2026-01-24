# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Version detection configuration
    #
    # @example Command-based version detection (GNU tools)
    #   vd = VersionDetection.new(
    #     command: '--version',
    #     pattern: '(\d+\.\d+)',
    #     modern_threshold: '7.0'
    #   )
    #
    # @example Man-page based version detection (BSD/system tools)
    #   vd = VersionDetection.new(
    #     command: ['man', 'find'],
    #     pattern: 'macOS ([\d.]+)',
    #     source: 'man'
    #   )
    class VersionDetection < Lutaml::Model::Serializable
      attribute :command, :string, collection: true, default: []
      attribute :pattern, :string
      attribute :modern_threshold, :string
      attribute :source, :string, default: 'command' # 'command' or 'man'

      yaml do
        map_element 'command', to: :command
        map_element 'pattern', to: :pattern
        map_element 'modern_threshold', to: :modern_threshold
        map_element 'source', to: :source
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
