# frozen_string_literal: true

module Ukiryu
  # Execution namespace for result models
  #
  # This namespace contains OOP models for command execution results,
  # providing a clean separation between execution logic and result modeling.
  module Execution
    # Autoload nested classes
    autoload :CommandInfo, 'ukiryu/execution/command_info'
    autoload :Output, 'ukiryu/execution/output'
    autoload :ExecutionMetadata, 'ukiryu/execution/metadata'
    autoload :Result, 'ukiryu/execution/result'
  end
end
