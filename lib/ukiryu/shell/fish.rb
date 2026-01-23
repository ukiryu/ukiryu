# frozen_string_literal: true

require_relative 'bash'

module Ukiryu
  module Shell
    # Fish shell implementation
    #
    # Fish uses similar quoting to Bash for most cases.
    class Fish < Bash
      def name
        :fish
      end
    end
  end
end
