# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::DefinitionLinter do
  describe '.lint' do
    context 'with valid minimal definition' do
      it 'returns issues but no errors' do
        definition = {
          name: 'test-tool',
          version: '1.0',
          description: 'A test tool',
          homepage: 'https://example.com',
          version_detection: { command: '--version', pattern: '(\d+\.\d+)' },
          profiles: [{
            name: 'default',
            platforms: %i[macos linux],
            commands: {
              test_command: {
                arguments: [{ name: 'input', type: 'file' }]
              }
            }
          }]
        }
        result = described_class.lint(definition)
        expect(result.has_issues?).to be true # Will have style issues about redundant default
        expect(result.has_errors?).to be false
      end
    end

    context 'with invalid tool name' do
      it 'returns warning about naming' do
        definition = { name: 'TestTool' }
        result = described_class.lint(definition)
        expect(result.has_issues?).to be true
        expect(result.warnings.first.message).to include('lowercase')
      end
    end

    context 'with missing description' do
      it 'returns info issue' do
        definition = { name: 'test' }
        result = described_class.lint(definition)
        expect(result.infos.any? { |i| i.message.include?('description') }).to be true
      end
    end

    context 'with missing homepage' do
      it 'returns info issue' do
        definition = { name: 'test' }
        result = described_class.lint(definition)
        expect(result.infos.any? { |i| i.message.include?('homepage') }).to be true
      end
    end

    context 'with missing version detection' do
      it 'returns warning' do
        definition = { name: 'test' }
        result = described_class.lint(definition)
        expect(result.warnings.any? { |i| i.message.include?('version detection') }).to be true
      end
    end

    context 'with suspicious subcommand' do
      it 'returns error' do
        definition = {
          name: 'test',
          profiles: [{
            name: 'default',
            commands: {
              dangerous: {
                subcommand: 'rm -rf /'
              }
            }
          }]
        }
        result = described_class.lint(definition)
        expect(result.errors.any? { |e| e.message.include?('dangerous') }).to be true
      end
    end

    context 'with unvalidated arguments' do
      it 'returns warning' do
        definition = {
          name: 'test',
          profiles: [{
            name: 'default',
            commands: {
              test_cmd: {
                arguments: [{ name: 'input' }]
              }
            }
          }]
        }
        result = described_class.lint(definition)
        expect(result.warnings.any? { |w| w.message.include?('type validation') }).to be true
      end
    end

    context 'with single default profile' do
      it 'returns style issue' do
        definition = {
          name: 'test',
          profiles: [{
            name: 'default',
            platforms: [:macos]
          }]
        }
        result = described_class.lint(definition)
        expect(result.styles.any? { |s| s.message.include?('redundant') }).to be true
      end
    end

    context 'with profile missing platforms' do
      it 'returns warning' do
        definition = {
          name: 'test',
          profiles: [{
            name: 'default'
          }]
        }
        result = described_class.lint(definition)
        expect(result.warnings.any? { |w| w.message.include?('platforms') }).to be true
      end
    end

    context 'with rule filtering' do
      it 'respects disabled rules' do
        definition = { name: 'TestTool' }
        result = described_class.lint(definition, rules: { disabled: ['naming_tool_name_format'] })
        expect(result.warnings.none? { |w| w.rule_id == 'naming_tool_name_format' }).to be true
      end

      it 'respects enabled rules' do
        definition = { name: 'TestTool' }
        result = described_class.lint(definition, rules: { enabled: ['naming_tool_name_format'] })
        expect(result.warnings.any? { |w| w.rule_id == 'naming_tool_name_format' }).to be true
      end
    end

    context 'when definition is not a hash' do
      it 'returns error' do
        result = described_class.lint('not-a-hash')
        expect(result.has_errors?).to be true
        expect(result.errors.first.message).to include('hash/object')
      end
    end
  end

  describe '.lint_file' do
    let(:fixture_path) { 'spec/fixtures/definitions' }

    context 'with existing valid file' do
      before do
        FileUtils.mkdir_p(fixture_path)
        File.write(
          File.join(fixture_path, 'test.yaml'),
          {
            name: 'test-tool',
            description: 'Test',
            profiles: [{
              name: 'default',
              platforms: [:macos],
              shells: [:bash]
            }]
          }.to_yaml
        )
      end

      after { FileUtils.rm_rf(fixture_path) }

      it 'lints the file' do
        result = described_class.lint_file(File.join(fixture_path, 'test.yaml'))
        expect(result).to be_a(described_class::LintResult)
      end
    end

    context 'with non-existent file' do
      it 'returns error' do
        result = described_class.lint_file('nonexistent.yaml')
        expect(result.has_errors?).to be true
        expect(result.errors.first.message).to include('File not found')
      end
    end

    context 'with invalid YAML' do
      before do
        FileUtils.mkdir_p(fixture_path)
        File.write(
          File.join(fixture_path, 'invalid.yaml'),
          "name: test\n  bad: indent"
        )
      end

      after { FileUtils.rm_rf(fixture_path) }

      it 'returns error' do
        result = described_class.lint_file(File.join(fixture_path, 'invalid.yaml'))
        expect(result.has_errors?).to be true
        expect(result.errors.first.message).to include('Invalid YAML')
      end
    end
  end

  describe '.lint_string' do
    context 'with valid YAML string' do
      it 'lints successfully' do
        yaml = { name: 'test-tool' }.to_yaml
        result = described_class.lint_string(yaml)
        expect(result).to be_a(described_class::LintResult)
      end
    end

    context 'with invalid YAML string' do
      it 'returns error' do
        result = described_class.lint_string('name: : test')
        expect(result.has_errors?).to be true
        expect(result.errors.first.message).to include('Invalid YAML')
      end
    end
  end

  describe Ukiryu::Definition::DefinitionLinter::LintResult do
    let(:result) do
      issues = [
        Ukiryu::Definition::LintIssue.error('Error 1'),
        Ukiryu::Definition::LintIssue.warning('Warning 1'),
        Ukiryu::Definition::LintIssue.info('Info 1'),
        Ukiryu::Definition::LintIssue.style('Style 1')
      ]
      Ukiryu::Definition::DefinitionLinter::LintResult.new(issues)
    end

    describe '#by_severity' do
      it 'filters issues by severity' do
        errors = result.by_severity(Ukiryu::Definition::LintIssue::SEVERITY_ERROR)
        expect(errors.length).to eq(1)
        expect(errors.first.message).to eq('Error 1')
      end
    end

    describe '#errors' do
      it 'returns error issues' do
        expect(result.errors.length).to eq(1)
        expect(result.errors.first).to be_an_error
      end
    end

    describe '#warnings' do
      it 'returns warning issues' do
        expect(result.warnings.length).to eq(1)
        expect(result.warnings.first).to be_a_warning
      end
    end

    describe '#infos' do
      it 'returns info issues' do
        expect(result.infos.length).to eq(1)
        expect(result.infos.first).to be_info
      end
    end

    describe '#styles' do
      it 'returns style issues' do
        expect(result.styles.length).to eq(1)
        expect(result.styles.first).to be_style
      end
    end

    describe '#count' do
      it 'returns total issue count' do
        expect(result.count).to eq(4)
      end
    end

    describe '#to_s' do
      it 'formats result as string' do
        output = result.to_s
        expect(output).to include('Found 4 issue(s)')
        expect(output).to include('ERROR:')
        expect(output).to include('WARNING:')
        expect(output).to include('INFO:')
        expect(output).to include('STYLE:')
      end
    end

    describe '#to_h' do
      it 'converts result to hash' do
        hash = result.to_h
        expect(hash[:total_count]).to eq(4)
        expect(hash[:error_count]).to eq(1)
        expect(hash[:warning_count]).to eq(1)
        expect(hash[:info_count]).to eq(1)
        expect(hash[:style_count]).to eq(1)
      end
    end
  end
end
