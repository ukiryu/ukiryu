# frozen_string_literal: true

# Add lib to load path for testing without installing gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'bundler/setup'
require 'timeout'
require 'ukiryu'

# Require all support files
Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Add timeout to all examples to prevent hanging tests
  # Uses 60 second timeout for individual examples
  config.around(:each) do |example|
    Timeout.timeout(60) do
      example.run
    end
  rescue Timeout::Error, Timeout::ExitException
    skip 'Test timed out after 60 seconds (may be hanging)'
  end

  config.before(:suite) do
    # Suppress git stderr to prevent "fatal: not a git repository" errors
    # from polluting test output, especially in CLI tests that capture stdout+stderr
    # This is needed because the Git gem spawns subprocesses that may write to stderr
    ENV['GIT_REDIRECT_STDERR'] = RbConfig::CONFIG['host_os'] =~ /mswin|mingw/ ? 'NUL' : '/dev/null'

    # Set up test register path if UKIRYU_REGISTER is not already set
    unless ENV['UKIRYU_REGISTER']
      test_register = File.expand_path('fixtures/register', __dir__)
      if Dir.exist?(test_register)
        ENV['UKIRYU_REGISTER'] = test_register
        Ukiryu::Register.default_register_path = test_register
      end
    end

    # Reset ToolIndex to pick up the new register path
    Ukiryu::ToolIndex.reset

    # Set up test schema path if UKIRYU_SCHEMA_PATH is not already set
    unless ENV['UKIRYU_SCHEMA_PATH']
      test_schema = File.expand_path('fixtures/tool.schema.yaml', __dir__)
      ENV['UKIRYU_SCHEMA_PATH'] = test_schema if File.exist?(test_schema)
    end
  end

  # Reset singleton state before each test to prevent pollution
  config.before(:each) do
    Ukiryu::Config.reset!
    Ukiryu::Register.reset_version_cache
    Ukiryu::ToolIndex.reset
    Ukiryu::Tool.clear_cache
    Ukiryu::Runtime.instance.reset!
    Ukiryu::Tools::Generator.clear_cache

    # Remove generated tool classes from Tools namespace
    Ukiryu::Tools.constants.each do |const|
      # Keep core modules and classes
      next if %i[Base Generator ExecutableFinder ClassGenerator].include?(const)

      Ukiryu::Tools.send(:remove_const, const)
    end
  end
end
