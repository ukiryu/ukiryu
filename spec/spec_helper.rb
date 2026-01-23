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

  # Set the default registry path for tests
  config.before(:suite) do
    # Register directory is at ../../register from the spec directory
    # (sibling to the ukiryu gem directory)
    registry_path = File.expand_path('../../register', __dir__)
    Ukiryu::Registry.default_registry_path = registry_path if Dir.exist?(registry_path)
  end

  # Reset singleton state before each test to prevent pollution
  config.before(:each) do
    Ukiryu::ToolIndex.reset
    Ukiryu::Tool.clear_cache
  end
end
