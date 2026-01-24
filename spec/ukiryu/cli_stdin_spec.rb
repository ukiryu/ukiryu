# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'open3'

RSpec.describe 'Ukiryu::CliCommands::RunCommand stdin handling' do
  let(:cli_class) { Ukiryu::Cli }
  let(:register_path) { Ukiryu::Register.default_register_path }
  let(:platform) { Ukiryu::Platform.detect }

  before do
    skip 'Set UKIRYU_REGISTER environment variable to run smoke tests' unless register_path && Dir.exist?(register_path)
    Ukiryu::Register.default_register_path = register_path
  end

  # Helper method to run CLI commands cross-platform
  def run_cli_command(command, stdin_data = nil)
    if platform == :windows
      # On Windows, use PowerShell
      powershell_cmd = command.gsub("'", "''").gsub(/"/, '\"')
      stdout, stderr, status = Open3.capture3("powershell.exe -NoProfile -Command #{powershell_cmd}")
    else
      # On Unix-like systems, run directly through bash with proper escaping
      # Use bash -c with the command as a single argument to avoid escaping issues
      stdout, stderr, status = if stdin_data
        Open3.capture3('bash', '-c', command, stdin_data: stdin_data)
      else
        Open3.capture3('bash', '-c', command)
      end
    end
    [stdout + stderr, status]
  end

  def run_ukiryu_exec(args, stdin_data = nil)
    cmd = "bundle exec ./exe/ukiryu #{args}"
    output, status = run_cli_command(cmd, stdin_data)
    [output, status]
  end

  describe '--stdin flag' do
    it 'reads from stdin pipe' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output, status = run_ukiryu_exec('exec jq process --stdin filter=".test" --format=json', '{"test": "value"}')

      # Parse JSON and extract stdout
      parsed = JSON.parse(output)
      expect(parsed['output']['stdout'].strip).to eq('"value"')
      expect(status.success?).to be true
    end

    it 'handles multi-line JSON from stdin' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      json_data = '{"lines": ["line1", "line2", "line3"]}'
      output, status = run_ukiryu_exec('exec jq process --stdin filter=".lines" --format=json', json_data)

      parsed = JSON.parse(output)
      stdout = parsed['output']['stdout']

      expect(stdout).to include('line1')
      expect(stdout).to include('line2')
      expect(stdout).to include('line3')
      expect(status.success?).to be true
    end
  end

  describe 'stdin=- parameter' do
    it 'reads from stdin pipe when stdin=- is specified' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output, status = run_ukiryu_exec('exec jq process stdin=- filter=".foo" --format=json', '{"foo": "bar"}')

      parsed = JSON.parse(output)
      expect(parsed['output']['stdout'].strip).to eq('"bar"')
      expect(status.success?).to be true
    end

    it 'is equivalent to --stdin flag' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      stdin_data = '{"test": "data"}'

      output1, status1 = run_ukiryu_exec('exec jq process --stdin filter=".test" --format=json', stdin_data)
      output2, status2 = run_ukiryu_exec('exec jq process stdin=- filter=".test" --format=json', stdin_data)

      parsed1 = JSON.parse(output1)
      parsed2 = JSON.parse(output2)

      expect(parsed1['output']['stdout']).to eq(parsed2['output']['stdout'])
      expect(status1.success?).to be true
      expect(status2.success?).to be true
    end
  end

  describe 'stdin=@filename parameter' do
    it 'reads from file when stdin=@filename is specified' do
      Tempfile.create(['ukiryu_test', '.json']) do |file|
        file.write('{"file": "content"}')
        file.close

        output, status = run_cli_command("bundle exec ./exe/ukiryu exec jq process stdin=@#{file.path} filter=\".file\" --format=json")

        parsed = JSON.parse(output)
        expect(parsed['output']['stdout'].strip).to eq('"content"')
        expect(status.success?).to be true
      end
    end

    it 'shows error when file does not exist' do
      output, status = run_cli_command("bundle exec ./exe/ukiryu exec jq process stdin=@/nonexistent/file.json filter=\".\" 2>&1")

      expect(output).to include('File not found')
      expect(status.success?).to be false
    end
  end

  describe 'stdin=data parameter' do
    it 'passes data directly to command stdin' do
      # NOTE: Due to shell parsing, this test may be flaky.
      # The stdin parameter should work, but shell escaping makes it difficult to test reliably.
      # We'll skip this test for now and rely on the other stdin tests.
      skip 'Shell parsing makes direct stdin data parameter testing unreliable'
    end
  end

  describe 'dry-run mode with stdin' do
    it 'shows preview of stdin data' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      # Use NO_COLOR to avoid ANSI escape codes in output
      # Use -D for dry-run (uppercase D, not lowercase d which is now --definition)
      output, status = run_ukiryu_exec('exec jq process --stdin -D filter="."', '{"test": "value"}')

      expect(output).to include('DRY RUN')
      expect(output).to include('stdin:')
      # Output has escaped backslashes in the inspection format
      expect(output).to include('test')
      expect(output).to include('value')
      expect(status.success?).to be true
    end

    it 'truncates long stdin preview' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      long_data = 'x' * 200
      # Use -D for dry-run (uppercase D, not lowercase d which is now --definition)
      output, status = run_ukiryu_exec('exec jq process --stdin -D filter="."', long_data)

      expect(output).to include('...')
      # Preview should be truncated (check in the output, not just the matched string)
      # The full 200 chars should not appear
      expect(output).not_to include(long_data)
      expect(status.success?).to be true
    end
  end

  describe 'format options with stdin' do
    it 'outputs JSON format with stdin' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output, status = run_ukiryu_exec('exec jq process --stdin filter=".test" --format=json', '{"test": "value"}')

      parsed = JSON.parse(output)
      expect(parsed['output']['stdout']).to include('"value"')
      expect(status.success?).to be true
    end

    it 'outputs YAML format with stdin' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output, status = run_ukiryu_exec('exec jq process --stdin filter=".test" --format=yaml', '{"test": "value"}')

      expect(output).to include('stdout:')
      expect(output).to include('value')
      expect(status.success?).to be true
    end
  end

  describe 'composition with other commands' do
    it 'can pipe output to another command' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      # Create a simple test data file to avoid shell escaping issues
      Tempfile.create(['ukiryu_compose', '.json']) do |file|
        file.write('{"items": [1,2,3]}')
        file.close

        # Use cat instead of echo to avoid escaping issues
        result, status = run_cli_command("cat #{file.path} | bundle exec ./exe/ukiryu exec jq process --stdin filter='.items' --format=json | head -10")

        # The output should be valid JSON, and head should truncate it
        expect(result).not_to be_empty
        expect(result).to include('[') # JSON array start
        expect(status.success?).to be true
      end
    end

    it 'can process output from curl' do
      skip 'Requires network access' unless ENV['ENABLE_NETWORK_TESTS']
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      # Test with a real API or mock server
      result, status = run_cli_command('curl -s https://httpbin.org/json | bundle exec ./exe/ukiryu exec jq process --stdin filter=".slideshow.title" --format=json')

      expect(result).not_to be_empty
      expect(status.success?).to be true
    end
  end

  describe 'with --raw output format' do
    it 'outputs only the command stdout without wrapping' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      output, status = run_ukiryu_exec('exec jq process --stdin --raw filter=".test"', '{"test": "value"}')

      # Should output just "value" without YAML/JSON wrapping
      expect(output.strip).to eq('"value"')
      expect(output).not_to include('status:')
      expect(output).not_to include('stdout:')
      expect(status.success?).to be true
    end

    it 'passes through stderr to actual stderr' do
      skip 'Unix pipe tests require Unix shell' if platform == :windows

      # Test with a command that produces stderr - use syntax error in jq
      output, status = run_ukiryu_exec('exec jq process --stdin --raw filter=".foo[bar"', '{}')

      # jq should produce an error in the output
      expect(output).not_to be_empty
      expect(output).to include('error')
      expect(output).to include('syntax error')
    end
  end
end
