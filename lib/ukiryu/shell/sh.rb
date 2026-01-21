# frozen_string_literal: true

require_relative "bash"

module Ukiryu
  module Shell
    # POSIX sh shell implementation
    #
    # sh uses the same quoting and escaping rules as Bash.
    class Sh < Bash
      def name
        :sh
      end
    end
  end
end
