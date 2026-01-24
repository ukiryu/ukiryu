# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::DefinitionValidator do
  describe '.schema_validation_available?' do
    it 'returns boolean indicating json-schema availability' do
      result = described_class.schema_validation_available?
      expect([true, false]).to include(result)
    end
  end

  describe '.validate' do
    context 'with valid minimal definition' do
      it 'returns success result' do
        definition = {
          name: 'test-tool',
          version: '1.0',
          profiles: []
        }
        result = described_class.validate(definition)
        expect(result).to be_valid
      end
    end

    context 'with missing name' do
      it 'returns failure result' do
        definition = { version: '1.0' }
        result = described_class.validate(definition)
        expect(result).to be_invalid
        # JSON Schema validation provides error message
        expect(result.errors).to_not be_empty
      end
    end

    context 'with name containing whitespace' do
      it 'returns error' do
        definition = { name: 'test tool' }
        result = described_class.validate(definition)
        expect(result).to be_invalid
        expect(result.errors).to include('Tool name must not contain whitespace')
      end
    end

    context 'with name starting with number' do
      it 'returns warning' do
        definition = { name: '3tool' }
        result = described_class.validate(definition)
        expect(result.has_warnings?).to be true
        expect(result.warnings).to include(/starting with number/)
      end
    end

    context 'with valid profiles' do
      it 'validates successfully' do
        definition = {
          name: 'test',
          version: '1.0',
          profiles: [
            {
              name: 'default',
              platforms: %i[macos linux],
              shells: %i[bash zsh],
              commands: []
            }
          ]
        }
        result = described_class.validate(definition)
        expect(result).to be_valid
      end
    end

    context 'with invalid profiles array' do
      it 'returns error' do
        definition = {
          name: 'test',
          profiles: 'not-an-array'
        }
        result = described_class.validate(definition)
        expect(result).to be_invalid
        # JSON Schema validation provides error message
        expect(result.errors).to_not be_empty
      end
    end

    context 'with schema version' do
      it 'validates valid schema version' do
        definition = {
          name: 'test',
          version: '1.0',
          ukiryu_schema: '1.0',
          profiles: []
        }
        result = described_class.validate(definition)
        expect(result).to be_valid
      end

      it 'warns about invalid schema version format' do
        definition = {
          name: 'test',
          version: '1.0',
          ukiryu_schema: 'invalid',
          profiles: []
        }
        result = described_class.validate(definition)
        expect(result.has_warnings?).to be true
        expect(result.warnings).to include(/Invalid schema version format/)
      end
    end

    context 'when definition is not a hash' do
      it 'returns error' do
        result = described_class.validate('not-a-hash')
        expect(result).to be_invalid
        expect(result.errors).to include('Definition must be a hash/object')
      end
    end
  end

  describe '.validate_file' do
    let(:fixture_path) { 'spec/fixtures/definitions' }

    context 'with existing valid file' do
      before do
        FileUtils.mkdir_p(fixture_path)
        File.write(
          File.join(fixture_path, 'valid.yaml'),
          {
            name: 'test',
            version: '1.0',
            profiles: [{
              name: 'default',
              platforms: [:macos],
              shells: [:bash]
            }]
          }.to_yaml
        )
      end

      after { FileUtils.rm_rf(fixture_path) }

      it 'validates the file' do
        result = described_class.validate_file(File.join(fixture_path, 'valid.yaml'))
        expect(result).to be_valid
      end
    end

    context 'with non-existent file' do
      it 'returns failure with file not found error' do
        result = described_class.validate_file('nonexistent.yaml')
        expect(result).to be_invalid
        expect(result.errors.first).to include('File not found')
      end
    end

    context 'with invalid YAML' do
      before do
        FileUtils.mkdir_p(fixture_path)
        File.write(
          File.join(fixture_path, 'invalid.yaml'),
          "name: test\n  bad: indentation\n    worse: here"
        )
      end

      after { FileUtils.rm_rf(fixture_path) }

      it 'returns failure with YAML error' do
        result = described_class.validate_file(File.join(fixture_path, 'invalid.yaml'))
        expect(result).to be_invalid
        expect(result.errors.first).to include('Invalid YAML')
      end
    end
  end

  describe '.validate_string' do
    context 'with valid YAML string' do
      it 'validates successfully' do
        yaml = { name: 'test', version: '1.0', profiles: [] }.to_yaml
        result = described_class.validate_string(yaml)
        expect(result).to be_valid
      end
    end

    context 'with invalid YAML string' do
      it 'returns failure' do
        result = described_class.validate_string('name: : test')
        expect(result).to be_invalid
        expect(result.errors.first).to include('Invalid YAML')
      end
    end
  end

  describe '.find_schema' do
    it 'returns the schema path from UKIRYU_SCHEMA_PATH environment variable if file exists' do
      original_env = ENV['UKIRYU_SCHEMA_PATH']
      temp_schema = nil
      begin
        # Create a temporary schema file
        temp_schema = File.expand_path('test_tool.schema.yaml', Dir.pwd)
        File.write(temp_schema, { type: 'object' }.to_yaml)
        ENV['UKIRYU_SCHEMA_PATH'] = temp_schema

        result = described_class.find_schema
        expect(result).to eq(temp_schema)
      ensure
        ENV['UKIRYU_SCHEMA_PATH'] = original_env
        File.delete(temp_schema) if temp_schema && File.exist?(temp_schema)
      end
    end

    it 'returns nil when UKIRYU_SCHEMA_PATH is set but file does not exist' do
      original_env = ENV['UKIRYU_SCHEMA_PATH']
      begin
        ENV['UKIRYU_SCHEMA_PATH'] = '/test/path/tool.schema.yaml'
        result = described_class.find_schema
        expect(result).to be_nil
      ensure
        ENV['UKIRYU_SCHEMA_PATH'] = original_env
      end
    end

    it 'returns nil when UKIRYU_SCHEMA_PATH is not set' do
      original_env = ENV.delete('UKIRYU_SCHEMA_PATH')
      result = described_class.find_schema
      expect(result).to be_nil
    ensure
      ENV['UKIRYU_SCHEMA_PATH'] = original_env if original_env
    end
  end
end
