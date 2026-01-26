# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Version detection method
    #
    # Single detection method in the fallback hierarchy
    class VersionDetectionMethod < Lutaml::Model::Serializable
      attribute :type, :string # 'command' or 'man_page'
      attribute :command, :string
      attribute :pattern, :string
      attribute :paths, :hash # Platform-specific paths for man_page

      yaml do
        map_element 'type', to: :type
        map_element 'command', to: :command
        map_element 'pattern', to: :pattern
        map_element 'paths', to: :paths
      end
    end

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
    #
    # @example Fallback hierarchy with detection_methods array
    #   vd = VersionDetection.new(
    #     detection_methods: [
    #       VersionDetectionMethod.new(type: 'command', command: '--version', pattern: '(\d+\.\d+)'),
    #       VersionDetectionMethod.new(type: 'man_page', paths: { macos: '/usr/share/man/man1/xargs.1' })
    #     ]
    #   )
    class VersionDetection < Lutaml::Model::Serializable
      attribute :command, :string, collection: true, default: []
      attribute :pattern, :string
      attribute :modern_threshold, :string
      attribute :source, :string, default: 'command' # 'command' or 'man'
      attribute :detection_methods, VersionDetectionMethod, collection: true, default: []

      yaml do
        map_element 'command', to: :command
        map_element 'pattern', to: :pattern
        map_element 'modern_threshold', to: :modern_threshold
        map_element 'source', to: :source
        map_element 'detection_methods', to: :detection_methods
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
