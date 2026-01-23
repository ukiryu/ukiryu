# frozen_string_literal: true

require 'lutaml/model'
require_relative 'arguments'

module Ukiryu
  module Models
    # Command execution information
    #
    # Contains details about the executed command including
    # the executable path, structured arguments, full command string, and shell used.
    class CommandInfo < Lutaml::Model::Serializable
      attribute :executable, :string
      attribute :executable_name, :string
      attribute :tool_name, :string  # Name of the tool being executed
      attribute :arguments, Arguments
      attribute :full_command, :string
      attribute :shell, :string

      yaml do
        map_element 'executable', to: :executable
        map_element 'executable_name', to: :executable_name
        map_element 'tool_name', to: :tool_name
        map_element 'arguments', to: :arguments
        map_element 'full_command', to: :full_command
        map_element 'shell', to: :shell
      end

      json do
        map 'executable', to: :executable
        map 'arguments', to: :arguments
        map 'full_command', to: :full_command
        map 'shell', to: :shell
      end
    end
  end
end
