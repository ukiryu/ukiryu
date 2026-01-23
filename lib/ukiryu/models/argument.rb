# frozen_string_literal: true

require 'lutaml/model'

module Ukiryu
  module Models
    # A single command argument
    #
    # Represents one argument with its name, value, and type information.
    class Argument < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :value, :string
      attribute :type, :string, default: 'argument'

      yaml do
        map_element 'name', to: :name
        map_element 'value', to: :value
        map_element 'type', to: :type
      end

      json do
        map 'name', to: :name
        map 'value', to: :value
        map 'type', to: :type
      end
    end
  end
end
