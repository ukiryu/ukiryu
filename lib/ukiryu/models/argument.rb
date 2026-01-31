# frozen_string_literal: true

module Ukiryu
  module Models
    # A single command argument
    #
    # Represents one argument with its name, value, and type information.
    class Argument < Lutaml::Model::Serializable
      attribute :name, :string
      attribute :value, :string
      attribute :type, :string, default: 'argument'

      key_value do
        map 'name', to: :name
        map 'value', to: :value
        map 'type', to: :type
      end
    end
  end
end
