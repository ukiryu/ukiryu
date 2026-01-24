# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::Loader do
  let(:valid_yaml) do
    <<~YAML
      name: test_tool
      version: "1.0"
      display_name: Test Tool
      homepage: https://example.com/test
      profiles:
        - name: default
          platforms: [linux, macos]
          shells: [bash, zsh]
          commands:
            - name: test_command
              description: A test command
    YAML
  end

  let(:invalid_yaml) do
    'name: test\n  invalid: [unclosed'
  end

  let(:missing_fields_yaml) do
    <<~YAML
      display_name: Test Tool
      # Missing: name, version, profiles
    YAML
  end

  let(:invalid_schema_yaml) do
    <<~YAML
      name: test
      version: "1.0"
      ukiryu_schema: "invalid"  # Not in X.Y format
      profiles:
        - name: default
    YAML
  end

  describe '.load_from_source' do
    let(:source) do
      Ukiryu::Definition::Sources::StringSource.new(valid_yaml)
    end

    it 'loads valid YAML into a ToolDefinition model' do
      profile = described_class.load_from_source(source)

      expect(profile).to be_a(Ukiryu::Models::ToolDefinition)
      expect(profile.name).to eq('test_tool')
      expect(profile.version).to eq('1.0')
    end

    it 'raises DefinitionLoadError for invalid YAML' do
      source = Ukiryu::Definition::Sources::StringSource.new(invalid_yaml)

      expect { described_class.load_from_source(source) }.to raise_error(
        Ukiryu::DefinitionLoadError,
        /Invalid YAML/
      )
    end

    it 'raises DefinitionLoadError with source info' do
      source = Ukiryu::Definition::Sources::StringSource.new(invalid_yaml)

      expect { described_class.load_from_source(source) }.to raise_error do |error|
        expect(error.message).to include(source.to_s)
      end
    end

    context 'with validation mode' do
      it 'validates in strict mode by default' do
        source = Ukiryu::Definition::Sources::StringSource.new(missing_fields_yaml)

        expect { described_class.load_from_source(source) }.to raise_error(
          Ukiryu::DefinitionValidationError,
          /Missing 'name' field/
        )
      end

      it 'validates with explicit strict mode' do
        source = Ukiryu::Definition::Sources::StringSource.new(missing_fields_yaml)

        expect { described_class.load_from_source(source, validation: :strict) }.to raise_error(
          Ukiryu::DefinitionValidationError
        )
      end

      it 'warns but does not raise in lenient mode' do
        source = Ukiryu::Definition::Sources::StringSource.new(missing_fields_yaml)

        expect { described_class.load_from_source(source, validation: :lenient) }.not_to raise_error
      end

      it 'skips validation in none mode' do
        source = Ukiryu::Definition::Sources::StringSource.new(missing_fields_yaml)

        result = described_class.load_from_source(source, validation: :none)

        expect(result).to be_a(Ukiryu::Models::ToolDefinition)
      end

      it 'validates ukiryu_schema format in strict mode' do
        source = Ukiryu::Definition::Sources::StringSource.new(invalid_schema_yaml)

        expect { described_class.load_from_source(source, validation: :strict) }.to raise_error(
          Ukiryu::DefinitionValidationError,
          /Invalid ukiryu_schema format/
        )
      end
    end
  end

  describe '.load_from_file' do
    let(:temp_dir) { Dir.mktmpdir('ukiryu-spec-') }
    let(:file_path) { File.join(temp_dir, 'test.yaml') }

    before do
      File.write(file_path, valid_yaml)
    end

    after do
      FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
    end

    it 'loads definition from file path' do
      profile = described_class.load_from_file(file_path)

      expect(profile).to be_a(Ukiryu::Models::ToolDefinition)
      expect(profile.name).to eq('test_tool')
    end

    it 'raises DefinitionNotFoundError for non-existent file' do
      expect { described_class.load_from_file('nonexistent.yaml') }.to raise_error(
        Ukiryu::DefinitionNotFoundError
      )
    end

    it 'passes options to load_from_source' do
      profile = described_class.load_from_file(file_path, validation: :none)

      expect(profile).to be_a(Ukiryu::Models::ToolDefinition)
    end
  end

  describe '.load_from_string' do
    it 'loads definition from YAML string' do
      profile = described_class.load_from_string(valid_yaml)

      expect(profile).to be_a(Ukiryu::Models::ToolDefinition)
      expect(profile.name).to eq('test_tool')
    end

    it 'raises DefinitionLoadError for invalid YAML string' do
      expect { described_class.load_from_string(invalid_yaml) }.to raise_error(
        Ukiryu::DefinitionLoadError
      )
    end

    it 'raises DefinitionLoadError for empty string' do
      expect { described_class.load_from_string('') }.to raise_error(
        Ukiryu::DefinitionLoadError,
        /cannot be empty/
      )
    end

    it 'passes options to load_from_source' do
      profile = described_class.load_from_string(valid_yaml, validation: :none)

      expect(profile).to be_a(Ukiryu::Models::ToolDefinition)
    end
  end

  describe '.profile_cache' do
    it 'returns a hash' do
      expect(described_class.profile_cache).to be_a(Hash)
    end

    it 'returns same cache on multiple calls' do
      cache1 = described_class.profile_cache
      cache2 = described_class.profile_cache

      expect(cache1).to be(cache2)
    end
  end

  describe '.clear_cache' do
    let(:source) { Ukiryu::Definition::Sources::StringSource.new(valid_yaml) }

    it 'clears all profiles when no source specified' do
      # Load something to populate cache
      described_class.load_from_source(source)

      described_class.clear_cache

      expect(described_class.profile_cache).to be_empty
    end

    it 'clears specific source profile' do
      # Load two different sources
      source1 = Ukiryu::Definition::Sources::StringSource.new(valid_yaml)
      source2 = Ukiryu::Definition::Sources::StringSource.new("name: other\nversion: \"1.0\"\nprofiles:\n  - name: default")

      described_class.load_from_source(source1)
      described_class.load_from_source(source2, validation: :strict)

      # Clear only source1
      described_class.clear_cache(source1)

      # Cache should have only source2
      expect(described_class.profile_cache.keys).to eq([source2.cache_key])
    end
  end

  describe 'validation' do
    context 'with valid profile' do
      it 'does not raise in strict mode' do
        source = Ukiryu::Definition::Sources::StringSource.new(valid_yaml)

        expect { described_class.load_from_source(source, validation: :strict) }.not_to raise_error
      end
    end

    context 'with missing required fields' do
      let(:invalid_profile) do
        <<~YAML
          display_name: Test
          # Missing: name, version, profiles
        YAML
      end

      it 'raises DefinitionValidationError for missing name' do
        source = Ukiryu::Definition::Sources::StringSource.new(invalid_profile)

        expect { described_class.load_from_source(source, validation: :strict) }.to raise_error do |error|
          expect(error.message).to include("Missing 'name' field")
        end
      end

      it 'raises DefinitionValidationError for missing version' do
        source = Ukiryu::Definition::Sources::StringSource.new(invalid_profile)

        expect { described_class.load_from_source(source, validation: :strict) }.to raise_error do |error|
          expect(error.message).to include("Missing 'version' field")
        end
      end

      it 'raises DefinitionValidationError for missing profiles' do
        source = Ukiryu::Definition::Sources::StringSource.new(invalid_profile)

        expect { described_class.load_from_source(source, validation: :strict) }.to raise_error do |error|
          expect(error.message).to include("Missing 'profiles' field")
        end
      end
    end

    context 'with empty profiles array' do
      let(:empty_profiles) do
        <<~YAML
          name: test
          version: "1.0"
          profiles: []
        YAML
      end

      it 'raises DefinitionValidationError' do
        source = Ukiryu::Definition::Sources::StringSource.new(empty_profiles)

        expect { described_class.load_from_source(source, validation: :strict) }.to raise_error do |error|
          expect(error.message).to include("Missing 'profiles' field or profiles is empty")
        end
      end
    end
  end

  describe '#sha256 (private method)' do
    it 'calculates SHA256 hash' do
      content = 'test content'
      expected_hash = Digest::SHA256.hexdigest(content)

      # We can't directly test private method, but we can verify through StringSource
      source = Ukiryu::Definition::Sources::StringSource.new(content)

      expect(source.content_hash).to eq(expected_hash)
    end
  end
end
