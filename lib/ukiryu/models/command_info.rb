# frozen_string_literal: true

module Ukiryu
  module Models
    # Command execution information
    #
    # Contains details about the executed command including
    # the executable path, structured arguments, full command string, and shell used.
    class CommandInfo < Lutaml::Model::Serializable
      attribute :executable, :string
      attribute :executable_name, :string
      attribute :tool_name, :string # Name of the tool being executed
      attribute :arguments, Arguments
      attribute :full_command, :string
      attribute :shell, :string

      key_value do
        map 'executable', to: :executable
        map 'executable_name', to: :executable_name
        map 'tool_name', to: :tool_name
        map 'arguments', to: :arguments
        map 'full_command', to: :full_command
        map 'shell', to: :shell
      end
    end
  end
end
