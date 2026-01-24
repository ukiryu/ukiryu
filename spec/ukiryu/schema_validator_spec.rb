# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe Ukiryu::SchemaValidator do
  describe '.validate_profile' do
    # Use UKIRYU_SCHEMA_PATH environment variable for schema location
    let(:schema_path) { ENV['UKIRYU_SCHEMA_PATH'] }

    before do
      skip 'Set UKIRYU_SCHEMA_PATH environment variable for schema validation tests' unless schema_path && File.exist?(schema_path)
    end

    context 'with valid Inkscape profile (from fixture)' do
      let(:profile_path) { File.join(__dir__, '../fixtures/profiles/inkscape_1.0.yaml') }
      let(:profile_content) { File.read(profile_path) }
      let(:profile) { YAML.safe_load(profile_content, permitted_classes: [], permitted_symbols: [], aliases: true) }

      it 'returns empty errors array' do
        symbolized_profile = symbolize_keys(profile)
        errors = described_class.validate_profile(symbolized_profile, schema_path: schema_path)
        expect(errors).to eq([])
      end
    end

    context 'with valid Ghostscript profile (from fixture)' do
      let(:profile_path) { File.join(__dir__, '../fixtures/profiles/ghostscript_10.0.yaml') }
      let(:profile_content) { File.read(profile_path) }
      let(:profile) { YAML.safe_load(profile_content, permitted_classes: [], permitted_symbols: [], aliases: true) }

      it 'returns empty errors array' do
        symbolized_profile = symbolize_keys(profile)
        errors = described_class.validate_profile(symbolized_profile, schema_path: schema_path)
        expect(errors).to eq([])
      end
    end

    context 'with minimal valid profile' do
      let(:profile) do
        {
          name: 'test_tool',
          version: '1.0',
          profiles: [
            {
              name: 'default',
              platforms: ['linux'],
              shells: ['bash'],
              commands: []
            }
          ]
        }
      end

      it 'returns empty errors array' do
        errors = described_class.validate_profile(profile, schema_path: schema_path)
        expect(errors).to eq([])
      end
    end

    context 'with missing required fields' do
      let(:profile) do
        {
          name: 'test_tool'
          # Missing version and profiles
        }
      end

      it 'returns errors for missing fields' do
        errors = described_class.validate_profile(profile, schema_path: schema_path)
        expect(errors).to_not be_empty
        expect(errors.any? { |e| e.include?('required') || e.include?('version') || e.include?('profiles') }).to be true
      end
    end

    context 'with invalid option type' do
      let(:profile) do
        {
          name: 'test_tool',
          version: '1.0',
          profiles: [
            {
              name: 'default',
              platforms: ['linux'],
              shells: ['bash'],
              commands: [
                {
                  name: 'convert',
                  options: [
                    {
                      name: 'quality',
                      type: 'invalid_type',
                      cli: '-q'
                    }
                  ]
                }
              ]
            }
          ]
        }
      end

      it 'returns errors for invalid enum values' do
        errors = described_class.validate_profile(profile, schema_path: schema_path)
        expect(errors).to_not be_empty
      end
    end
  end

  describe '.default_schema_path' do
    it 'returns nil when UKIRYU_SCHEMA_PATH is not set' do
      original_env = ENV.delete('UKIRYU_SCHEMA_PATH')
      path = described_class.default_schema_path
      expect(path).to be_nil
    ensure
      ENV['UKIRYU_SCHEMA_PATH'] = original_env if original_env
    end

    it 'returns the schema path from UKIRYU_SCHEMA_PATH environment variable' do
      original_env = ENV['UKIRYU_SCHEMA_PATH']
      temp_schema = nil
      begin
        # Create a temporary schema file
        temp_schema = File.expand_path('test_tool.schema.yaml', Dir.pwd)
        File.write(temp_schema, { type: 'object' }.to_yaml)
        ENV['UKIRYU_SCHEMA_PATH'] = temp_schema

        path = described_class.default_schema_path
        expect(path).to eq(temp_schema)
      ensure
        ENV['UKIRYU_SCHEMA_PATH'] = original_env
        File.delete(temp_schema) if temp_schema && File.exist?(temp_schema)
      end
    end
  end

  # Helper method to symbolize keys recursively (matches Register behavior)
  def symbolize_keys(hash)
    return hash unless hash.is_a?(Hash)

    hash.transform_keys do |key|
      key.is_a?(String) ? key.to_sym : key
    end.transform_values do |value|
      case value
      when Hash
        symbolize_keys(value)
      when Array
        value.map { |v| v.is_a?(Hash) ? symbolize_keys(v) : v }
      else
        value
      end
    end
  end
end
