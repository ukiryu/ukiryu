# frozen_string_literal: true

require_relative 'bash'

module Ukiryu
  module Shell
    # Zsh shell implementation
    #
    # Zsh uses the same quoting and escaping rules as Bash.
    class Zsh < Bash
      def name
        :zsh
      end
    end
  end
end
