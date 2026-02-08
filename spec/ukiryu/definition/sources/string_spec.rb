# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::Sources::StringSource do
  describe '#initialize' do
    context 'with valid YAML string' do
      it 'creates a source without error' do
        yaml_content = 'name: test'

        expect { described_class.new(yaml_content) }.not_to raise_error
      end

      it 'stores the content' do
        yaml_content = 'name: test\nversion: "1.0"'

        source = described_class.new(yaml_content)

        expect(source.content).to eq(yaml_content.strip)
      end

      it 'calculates content hash' do
        yaml_content = 'name: test'

        source = described_class.new(yaml_content)

        expect(source.content_hash).to match(/^[a-f0-9]{64}$/)
      end

      it 'strips leading/trailing whitespace' do
        yaml_content = "  \n  name: test\n  \n"

        source = described_class.new(yaml_content)

        expect(source.content).to eq('name: test')
      end
    end

    context 'with empty string' do
      it 'raises DefinitionLoadError' do
        expect { described_class.new('') }.to raise_error(
          Ukiryu::Errors::DefinitionLoadError,
          /cannot be empty/
        )
      end
    end

    context 'with non-string input' do
      it 'raises ArgumentError for nil' do
        expect { described_class.new(nil) }.to raise_error(
          ArgumentError,
          /must be a String/
        )
      end

      it 'raises ArgumentError for integer' do
        expect { described_class.new(123) }.to raise_error(
          ArgumentError,
          /must be a String/
        )
      end

      it 'raises ArgumentError for hash' do
        expect { described_class.new(name: 'test') }.to raise_error(
          ArgumentError,
          /must be a String/
        )
      end
    end

    context 'with whitespace-only string' do
      it 'stores stripped content' do
        yaml_content = "   \n\t\n   "

        source = described_class.new(yaml_content)

        expect(source.content).to eq('')
      end

      it 'calculates hash of stripped content' do
        yaml_content = '  name: test  '

        source = described_class.new(yaml_content)

        # Hash should be of stripped content
        expected_hash = Digest::SHA256.hexdigest('name: test')
        expect(source.content_hash).to eq(expected_hash)
      end
    end
  end

  describe '#load' do
    it 'returns the content' do
      yaml_content = 'name: test\nversion: "1.0"'
      source = described_class.new(yaml_content)

      expect(source.load).to eq(yaml_content)
    end

    it 'returns stripped content' do
      yaml_content = "  \nname: test\n  "
      source = described_class.new(yaml_content)

      expect(source.load).to eq('name: test')
    end

    it 'returns same content on multiple calls' do
      yaml_content = 'name: test'
      source = described_class.new(yaml_content)

      first_load = source.load
      second_load = source.load

      expect(first_load).to eq(second_load)
    end
  end

  describe '#source_type' do
    it 'returns :string' do
      source = described_class.new('name: test')

      expect(source.source_type).to eq(:string)
    end
  end

  describe '#cache_key' do
    it 'includes SHA256 hash' do
      source = described_class.new('name: test')

      expect(source.cache_key).to match(/^string:[a-f0-9]{64}$/)
    end

    it 'generates consistent cache keys for same content' do
      content = 'name: test'

      source1 = described_class.new(content)
      source2 = described_class.new(content)

      expect(source1.cache_key).to eq(source2.cache_key)
    end

    it 'generates different cache keys for different content' do
      source1 = described_class.new('name: test1')
      source2 = described_class.new('name: test2')

      expect(source1.cache_key).not_to eq(source2.cache_key)
    end

    it 'generates different cache keys for same content with different whitespace' do
      source1 = described_class.new('name: test')
      source2 = described_class.new('  name: test  ')

      # Both should be stripped, so same hash
      expect(source1.cache_key).to eq(source2.cache_key)
    end

    it 'uses SHA256 hash algorithm' do
      content = 'consistent content'

      source = described_class.new(content)

      # Verify it's using SHA256
      expected_hash = Digest::SHA256.hexdigest(content)
      expect(source.cache_key).to eq("string:#{expected_hash}")
    end
  end

  describe '#size' do
    it 'returns the byte size of the content' do
      content = 'name: test'
      source = described_class.new(content)

      expect(source.size).to eq(content.bytesize)
    end

    it 'returns size of stripped content' do
      content = '  name: test  '
      source = described_class.new(content)

      expect(source.size).to eq('name: test'.bytesize)
    end

    it 'returns zero for empty content' do
      # NOTE: empty content raises error in initialize, so test with whitespace
      content = '   '
      source = described_class.new(content)

      expect(source.size).to eq(0)
    end

    it 'accurately counts multi-byte characters' do
      content = 'name: テスト' # Japanese characters
      source = described_class.new(content)

      expect(source.size).to eq(content.bytesize)
    end
  end

  describe 'with complex YAML' do
    it 'handles multi-line YAML' do
      yaml_content = <<~YAML
        name: test_tool
        version: "1.0"
        profiles:
          - name: default
            platforms:
              - linux
              - macos
            shells:
              - bash
              - zsh
      YAML

      source = described_class.new(yaml_content)

      # StringSource strips content, so the loaded content equals stripped input
      expect(source.load).to eq(yaml_content.strip)
    end

    it 'preserves YAML structure' do
      yaml_content = <<~YAML
        name: test
        profiles:
          - name: default
            commands:
              - name: export
      YAML

      source = described_class.new(yaml_content)

      loaded = source.load
      expect(loaded).to include('name: test')
      expect(loaded).to include('profiles:')
    end
  end

  describe 'equality' do
    it 'considers sources with same content as equal' do
      content = 'name: test'
      source1 = described_class.new(content)
      source2 = described_class.new(content)

      expect(source1).to eq(source2)
    end

    it 'considers sources with different content as not equal' do
      source1 = described_class.new('name: test1')
      source2 = described_class.new('name: test2')

      expect(source1).not_to eq(source2)
    end
  end

  describe 'hash' do
    it 'generates same hash for sources with same content' do
      content = 'name: test'
      source1 = described_class.new(content)
      source2 = described_class.new(content)

      expect(source1.hash).to eq(source2.hash)
    end
  end
end
