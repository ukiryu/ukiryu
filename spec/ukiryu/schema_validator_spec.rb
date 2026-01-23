# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe Ukiryu::SchemaValidator do
  describe '.validate_profile' do
    # Helper to get the register directory
    let(:register_dir) { '/Users/mulgogi/src/ukiryu/register' }
    let(:schema_path) { '/Users/mulgogi/src/ukiryu/schema/tool-profile.schema.yaml' }

    context 'with valid Inkscape profile' do
      let(:profile_path) { File.join(register_dir, 'tools/inkscape/1.0.yaml') }
      let(:profile_content) { File.read(profile_path) }
      let(:profile) { YAML.safe_load(profile_content, permitted_classes: [], permitted_symbols: [], aliases: true) }

      it 'returns empty errors array' do
        symbolized_profile = symbolize_keys(profile)
        errors = described_class.validate_profile(symbolized_profile, schema_path: schema_path)
        expect(errors).to eq([])
      end
    end

    context 'with valid Ghostscript profile' do
      let(:profile_path) { File.join(register_dir, 'tools/ghostscript/10.0.yaml') }
      let(:profile_content) { File.read(profile_path) }
      let(:profile) { YAML.safe_load(profile_content, permitted_classes: [], permitted_symbols: [], aliases: true) }

      it 'returns empty errors array' do
        symbolized_profile = symbolize_keys(profile)
        errors = described_class.validate_profile(symbolized_profile, schema_path: schema_path)
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

    context 'with invalid platforms' do
      let(:profile) do
        {
          name: 'test_tool',
          version: '1.0',
          profiles: [
            {
              name: 'test_profile',
              platforms: ['invalid_platform'], # Invalid
              shells: ['bash'],
              commands: {}
            }
          ]
        }
      end

      it 'returns error for invalid platform' do
        errors = described_class.validate_profile(profile, schema_path: schema_path)
        expect(errors).to_not be_empty
        # JSON schema validation will catch enum violations
      end
    end

    context 'with invalid shells' do
      let(:profile) do
        {
          name: 'test_tool',
          version: '1.0',
          profiles: [
            {
              name: 'test_profile',
              platforms: ['linux'],
              shells: ['invalid_shell'], # Invalid
              commands: {}
            }
          ]
        }
      end

      it 'returns error for invalid shell' do
        errors = described_class.validate_profile(profile, schema_path: schema_path)
        expect(errors).to_not be_empty
      end
    end
  end

  describe '.default_schema_path' do
    it 'returns the schema path' do
      path = described_class.default_schema_path
      expect(path).to_not be_nil
      expect(File.exist?(path)).to be true
    end
  end

  # Helper method to symbolize keys recursively (matches Registry behavior)
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
