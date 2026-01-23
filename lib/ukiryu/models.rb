# frozen_string_literal: true

require_relative 'models/tool_metadata'
require_relative 'models/tool_definition'
require_relative 'models/platform_profile'
require_relative 'models/command_definition'
require_relative 'models/option_definition'
require_relative 'models/flag_definition'
require_relative 'models/argument_definition'
require_relative 'models/version_detection'
require_relative 'models/search_paths'
require_relative 'models/execution_report'
require_relative 'models/version_compatibility'
require_relative 'models/exit_codes'
require_relative 'models/components'

module Ukiryu
  module Models
    # Models namespace for tool profile model classes
    #
    # These models use lutaml-model for proper YAML serialization/deserialization
  end
end
