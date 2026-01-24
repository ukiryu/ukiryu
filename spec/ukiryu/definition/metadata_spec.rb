# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::DefinitionMetadata do
  let(:valid_path) { '/path/to/tool/1.0.yaml' }

  describe '#initialize' do
    it 'creates metadata with all required attributes' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      expect(metadata.name).to eq('test_tool')
      expect(metadata.version).to eq('1.0')
      expect(metadata.path).to eq(File.expand_path(valid_path))
      expect(metadata.source_type).to eq(:user)
    end
  end

  describe '#load_definition' do
    let(:temp_dir) { Dir.mktmpdir('ukiryu-spec-') }
    let(:yaml_content) do
      <<~YAML
        name: test_tool
        version: "1.0"
        profiles:
          - name: default
            platforms: [linux]
            shells: [bash]
      YAML
    end

    after do
      FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
    end

    it 'loads the definition from the file' do
      file_path = File.join(temp_dir, 'test_tool.yaml')
      File.write(file_path, yaml_content)

      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0',
        path: file_path,
        source_type: :user
      )

      definition = metadata.load_definition

      expect(definition).to be_a(Ukiryu::Models::ToolDefinition)
      expect(definition.name).to eq('test_tool')
    end
  end

  describe '#exists?' do
    it 'returns true when file exists' do
      temp_dir = Dir.mktmpdir('ukiryu-spec-')
      file_path = File.join(temp_dir, 'tool.yaml')
      File.write(file_path, 'name: test')

      metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: file_path,
        source_type: :user
      )

      expect(metadata.exists?).to be true

      FileUtils.rm_rf(temp_dir)
    end

    it 'returns false when file does not exist' do
      metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: '/nonexistent/path.yaml',
        source_type: :user
      )

      expect(metadata.exists?).to be false
    end
  end

  describe '#mtime' do
    it 'returns file modification time when file exists' do
      temp_dir = Dir.mktmpdir('ukiryu-spec-')
      file_path = File.join(temp_dir, 'tool.yaml')
      File.write(file_path, 'name: test')

      metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: file_path,
        source_type: :user
      )

      expect(metadata.mtime).to be_a(Time)

      FileUtils.rm_rf(temp_dir)
    end

    it 'returns nil when file does not exist' do
      metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: '/nonexistent/path.yaml',
        source_type: :user
      )

      expect(metadata.mtime).to be_nil
    end
  end

  describe '#to_s' do
    it 'returns readable string representation' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      expect(metadata.to_s).to include('test_tool')
      expect(metadata.to_s).to include('1.0')
      expect(metadata.to_s).to include('user')
    end
  end

  describe '#inspect' do
    it 'returns detailed inspection string' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      inspection = metadata.inspect

      expect(inspection).to include('DefinitionMetadata')
      expect(inspection).to include('test_tool')
      expect(inspection).to include('1.0')
    end
  end

  describe '#==' do
    it 'considers equal metadata as equal' do
      metadata1 = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      metadata2 = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      expect(metadata1).to eq(metadata2)
    end

    it 'considers different names as not equal' do
      metadata1 = described_class.new(
        name: 'test1',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      metadata2 = described_class.new(
        name: 'test2',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      expect(metadata1).not_to eq(metadata2)
    end
  end

  describe '#hash' do
    it 'generates same hash for equal metadata' do
      metadata1 = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      metadata2 = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      expect(metadata1.hash).to eq(metadata2.hash)
    end
  end

  describe '#priority' do
    it 'returns priority based on source type' do
      user_metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      bundled_metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :bundled
      )

      system_metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :system
      )

      expect(user_metadata.priority).to be < bundled_metadata.priority
      expect(bundled_metadata.priority).to be < system_metadata.priority
    end

    it 'assigns high priority to unknown source types' do
      metadata = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :unknown
      )

      expect(metadata.priority).to eq(999)
    end
  end

  describe '#<=>' do
    it 'sorts by priority first' do
      metadata1 = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      metadata2 = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :system
      )

      expect(metadata1 <=> metadata2).to be < 0
    end

    it 'sorts by version (descending) when priority is same' do
      metadata1 = described_class.new(
        name: 'test',
        version: '2.0',
        path: valid_path,
        source_type: :user
      )

      metadata2 = described_class.new(
        name: 'test',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      expect(metadata1 <=> metadata2).to be < 0
    end

    it 'sorts by name when priority and version are same' do
      metadata1 = described_class.new(
        name: 'aaa',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      metadata2 = described_class.new(
        name: 'zzz',
        version: '1.0',
        path: valid_path,
        source_type: :user
      )

      expect(metadata1 <=> metadata2).to be < 0
    end
  end
end
