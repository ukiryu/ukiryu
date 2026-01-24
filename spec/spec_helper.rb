# frozen_string_literal: true

require 'bundler/setup'
require 'ukiryu'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Set the default register path for tests
  config.before(:suite) do
    # Set up test register path if UKIRYU_REGISTER is not already set
    unless ENV['UKIRYU_REGISTER']
      test_register = File.expand_path('fixtures/register', __dir__)
      if Dir.exist?(test_register)
        ENV['UKIRYU_REGISTER'] = test_register
        Ukiryu::Register.default_register_path = test_register
      end
    end

    # Set up test schema path if UKIRYU_SCHEMA_PATH is not already set
    unless ENV['UKIRYU_SCHEMA_PATH']
      test_schema = File.expand_path('fixtures/tool.schema.yaml', __dir__)
      if File.exist?(test_schema)
        ENV['UKIRYU_SCHEMA_PATH'] = test_schema
      end
    end
  end

  # Reset singleton state before each test to prevent pollution
  config.before(:each) do
    Ukiryu::ToolIndex.reset
    Ukiryu::Tool.clear_cache
  end
end
