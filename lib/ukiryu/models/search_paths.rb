# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # Search paths configuration for finding tool executables
    #
    # @example
    #   sp = SearchPaths.new
    #   sp.macos = ['/opt/homebrew/bin/tool']
    #   sp.linux = ['/usr/bin/tool']
    class SearchPaths < Lutaml::Model::Serializable
      attribute :macos, :string, collection: true, default: []
      attribute :linux, :string, collection: true, default: []
      attribute :windows, :string, collection: true, default: []
      attribute :freebsd, :string, collection: true, default: []
      attribute :openbsd, :string, collection: true, default: []
      attribute :netbsd, :string, collection: true, default: []

      yaml do
        map_element 'macos', to: :macos
        map_element 'linux', to: :linux
        map_element 'windows', to: :windows
        map_element 'freebsd', to: :freebsd
        map_element 'openbsd', to: :openbsd
        map_element 'netbsd', to: :netbsd
      end

      # Get search paths for a specific platform
      #
      # @param platform [Symbol] the platform
      # @return [Array<String>] the search paths
      def for_platform(platform)
        send(platform) || []
      end
    end
  end
end
