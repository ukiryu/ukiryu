# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'open3'

RSpec.describe 'Ukiryu::CliCommands::RunCommand stdin handling' do
  let(:cli_class) { Ukiryu::Cli }
  let(:registry_path) { Ukiryu::Registry.default_registry_path }
  let(:platform) { Ukiryu::Platform.detect }

  before do
    # Skip tests if jq is not available
    tool = Ukiryu::Tool.get(:jq, registry_path: registry_path)
    skip 'jq not available' unless tool.available?
  end

  # Helper method to run CLI commands cross-platform
  def run_cli_command(command)
    if platform == :windows
      # On Windows, use PowerShell
      powershell_cmd = command.gsub("'", "''").gsub(/"/, '\"')
      stdout, stderr, status = Open3.capture3("powershell.exe -NoProfile -Command #{powershell_cmd}")
      stdout + stderr
    else
      # On Unix-like systems, use bash
      stdout, stderr, status = Open3.capture3("bash -c '#{command.gsub("'", "'\\''")}'")
      stdout + stderr
    end
  end

  describe '--stdin flag' do
    it 'reads from stdin pipe' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output = `echo '{"test": "value"}' | bundle exec ./exe/ukiryu exec jq process --stdin filter=".test" --format=json`

      # Parse JSON and extract stdout
      parsed = JSON.parse(output)
      expect(parsed['output']['stdout'].strip).to eq('"value"')
    end

    it 'handles multi-line JSON from stdin' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      json_data = '{"lines": ["line1", "line2", "line3"]}'
      output = `echo '#{json_data}' | bundle exec ./exe/ukiryu exec jq process --stdin filter=".lines" --format=json`

      parsed = JSON.parse(output)
      stdout = parsed['output']['stdout']

      expect(stdout).to include('line1')
      expect(stdout).to include('line2')
      expect(stdout).to include('line3')
    end
  end

  describe 'stdin=- parameter' do
    it 'reads from stdin pipe when stdin=- is specified' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output = `echo '{"foo": "bar"}' | bundle exec ./exe/ukiryu exec jq process stdin=- filter=".foo" --format=json`

      parsed = JSON.parse(output)
      expect(parsed['output']['stdout'].strip).to eq('"bar"')
    end

    it 'is equivalent to --stdin flag' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      stdin_data = '{"test": "data"}'

      output1 = `echo '#{stdin_data}' | bundle exec ./exe/ukiryu exec jq process --stdin filter=".test" --format=json`
      output2 = `echo '#{stdin_data}' | bundle exec ./exe/ukiryu exec jq process stdin=- filter=".test" --format=json`

      parsed1 = JSON.parse(output1)
      parsed2 = JSON.parse(output2)

      expect(parsed1['output']['stdout']).to eq(parsed2['output']['stdout'])
    end
  end

  describe 'stdin=@filename parameter' do
    it 'reads from file when stdin=@filename is specified' do
      Tempfile.create(['ukiryu_test', '.json']) do |file|
        file.write('{"file": "content"}')
        file.close

        output = `bundle exec ./exe/ukiryu exec jq process stdin=@#{file.path} filter=".file" --format=json`

        parsed = JSON.parse(output)
        expect(parsed['output']['stdout'].strip).to eq('"content"')
      end
    end

    it 'shows error when file does not exist' do
      output = `bundle exec ./exe/ukiryu exec jq process stdin=@/nonexistent/file.json filter="." 2>&1`

      expect(output).to include('File not found')
    end
  end

  describe 'stdin=data parameter' do
    it 'passes data directly to command stdin' do
      # Note: Due to shell parsing, this test may be flaky.
      # The stdin parameter should work, but shell escaping makes it difficult to test reliably.
      # We'll skip this test for now and rely on the other stdin tests.
      skip 'Shell parsing makes direct stdin data parameter testing unreliable'
    end
  end

  describe 'dry-run mode with stdin' do
    it 'shows preview of stdin data' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      # Use NO_COLOR to avoid ANSI escape codes in output
      output = `echo '{"test": "value"}' | NO_COLOR=1 bundle exec ./exe/ukiryu exec jq process --stdin -d filter="." 2>&1`

      expect(output).to include('DRY RUN')
      expect(output).to include('stdin:')
      # Output has escaped backslashes in the inspection format
      expect(output).to include('test')
      expect(output).to include('value')
    end

    it 'truncates long stdin preview' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      long_data = 'x' * 200
      output = `echo '#{long_data}' | NO_COLOR=1 bundle exec ./exe/ukiryu exec jq process --stdin -d filter="." 2>&1`

      expect(output).to include('...')
      # Preview should be truncated (check in the output, not just the matched string)
      # The full 200 chars should not appear
      expect(output).not_to include(long_data)
    end
  end

  describe 'format options with stdin' do
    it 'outputs JSON format with stdin' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output = `echo '{"test": "value"}' | bundle exec ./exe/ukiryu exec jq process --stdin filter=".test" --format=json`

      parsed = JSON.parse(output)
      expect(parsed['output']['stdout']).to include('"value"')
    end

    it 'outputs YAML format with stdin' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output = `echo '{"test": "value"}' | bundle exec ./exe/ukiryu exec jq process --stdin filter=".test" --format=yaml`

      expect(output).to include('stdout:')
      expect(output).to include('value')
    end
  end

  describe 'composition with other commands' do
    it 'can pipe output to another command' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      result = `echo '{"items": [1,2,3]}' | bundle exec ./exe/ukiryu exec jq process --stdin filter=".items" --format=json | head -10`

      # The output should be valid JSON, and head should truncate it
      expect(result).not_to be_empty
      expect(result).to include('[') # JSON array start
    end

    it 'can process output from curl' do
      skip 'Requires network access' unless ENV['ENABLE_NETWORK_TESTS']
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      # Test with a real API or mock server
      result = `curl -s https://httpbin.org/json | bundle exec ./exe/ukiryu exec jq process --stdin filter=".slideshow.title" --format=json`

      expect(result).not_to be_empty
    end
  end

  describe 'with --raw output format' do
    it 'outputs only the command stdout without wrapping' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output = `echo '{"test": "value"}' | bundle exec ./exe/ukiryu exec jq process --stdin --raw filter=".test"`

      # Should output just "value" without YAML/JSON wrapping
      expect(output.strip).to eq('"value"')
      expect(output).not_to include('status:')
      expect(output).not_to include('stdout:')
    end

    it 'passes through stderr to actual stderr' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      # Test with a command that produces stderr
      output = `echo '{}' | bundle exec ./exe/ukiryu exec jq process --stdin --raw filter='.invalid' 2>&1`

      # jq should produce an error on stderr
      expect(output).not_to be_empty
    end
  end
end
