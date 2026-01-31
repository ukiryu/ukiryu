# frozen_string_literal: true

module Ukiryu
  module Extractors
    # Extractors namespace for tool definition extraction strategies
    #
    # These classes provide different strategies for extracting tool
    # definitions from CLI tools (native flags, help parsing, etc.)

    # Autoload extractor classes
    autoload :BaseExtractor, 'ukiryu/extractors/base_extractor'
    autoload :Extractor, 'ukiryu/extractors/extractor'
    autoload :NativeExtractor, 'ukiryu/extractors/native_extractor'
    autoload :HelpParser, 'ukiryu/extractors/help_parser'
  end
end
