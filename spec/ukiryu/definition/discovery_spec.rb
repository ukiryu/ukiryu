# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::Discovery do
  let(:temp_dir) { Dir.mktmpdir('ukiryu-spec-') }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe '.xdg_data_home' do
    it 'returns XDG_DATA_HOME environment variable if set' do
      original_value = ENV['XDG_DATA_HOME']
      begin
        ENV['XDG_DATA_HOME'] = '/custom/data'
        expect(described_class.xdg_data_home).to eq('/custom/data')
      ensure
        ENV['XDG_DATA_HOME'] = original_value
      end
    end

    it 'returns default ~/.local/share if XDG_DATA_HOME not set' do
      original_value = ENV.delete('XDG_DATA_HOME')
      begin
        expect(described_class.xdg_data_home).to eq(File.expand_path('~/.local/share'))
      ensure
        ENV['XDG_DATA_HOME'] = original_value
      end
    end
  end

  describe '.xdg_data_dirs' do
    it 'returns XDG_DATA_DIRS environment variable if set' do
      original_value = ENV['XDG_DATA_DIRS']
      begin
        ENV['XDG_DATA_DIRS'] = '/path1:/path2'
        expect(described_class.xdg_data_dirs).to eq(['/path1', '/path2'])
      ensure
        ENV['XDG_DATA_DIRS'] = original_value
      end
    end

    it 'returns default paths if XDG_DATA_DIRS not set' do
      original_value = ENV.delete('XDG_DATA_DIRS')
      begin
        expect(described_class.xdg_data_dirs).to eq(['/usr/local/share', '/usr/share'])
      ensure
        ENV['XDG_DATA_DIRS'] = original_value
      end
    end
  end

  describe '.user_definitions_directory' do
    it 'returns path to user definitions directory' do
      expected = File.join(described_class.xdg_data_home, 'ukiryu', 'definitions')
      expect(described_class.user_definitions_directory).to eq(expected)
    end
  end

  describe '.search_paths' do
    it 'includes user definitions directory' do
      paths = described_class.search_paths
      expect(paths).to include(described_class.user_definitions_directory)
    end

    it 'includes system data directories' do
      paths = described_class.search_paths
      expect(paths).to include('/usr/local/share/ukiryu/definitions')
      expect(paths).to include('/usr/share/ukiryu/definitions')
    end
  end

  describe '.tool_bundled_paths' do
    it 'returns array of paths' do
      paths = described_class.tool_bundled_paths
      expect(paths).to be_an(Array)
    end
  end

  describe '.discover' do
    let(:user_dir) { File.join(temp_dir, 'definitions') }

    before do
      # Create a test definition in user directory
      tool_dir = File.join(user_dir, 'test_tool')
      FileUtils.mkdir_p(tool_dir)

      File.write(File.join(tool_dir, '1.0.yaml'), <<~YAML)
        name: test_tool
        version: "1.0"
        profiles:
          - name: default
            platforms: [linux]
            shells: [bash]
      YAML
    end

    context 'when definitions exist' do
      it 'returns hash of tool names to metadata' do
        # Mock the search_paths to only include our test directory
        allow(described_class).to receive(:search_paths).and_return([user_dir])

        # Mock user_definitions_directory to return our test directory
        allow(described_class).to receive(:user_definitions_directory).and_return(user_dir)

        # Mock determine_source_type to return :user
        allow(described_class).to receive(:determine_source_type).with(user_dir).and_return(:user)

        definitions = described_class.discover

        expect(definitions).to be_a(Hash)
        expect(definitions.key?('test_tool')).to be true
      end

      it 'sorts definitions by priority' do
        allow(described_class).to receive(:search_paths).and_return([user_dir])
        allow(described_class).to receive(:user_definitions_directory).and_return(user_dir)
        allow(described_class).to receive(:determine_source_type).with(user_dir).and_return(:user)

        definitions = described_class.discover
        test_tool_defs = definitions['test_tool']

        expect(test_tool_defs).to be_an(Array)
        expect(test_tool_defs.first.source_type).to eq(:user)
      end
    end

    context 'when no definitions exist' do
      it 'returns empty hash' do
        empty_dir = File.join(temp_dir, 'empty')
        FileUtils.mkdir_p(empty_dir)

        allow(described_class).to receive(:search_paths).and_return([empty_dir])

        definitions = described_class.discover

        expect(definitions).to eq({})
      end
    end
  end

  describe '.find' do
    let(:user_dir) { File.join(temp_dir, 'definitions') }

    before do
      # Create test definitions
      tool_dir = File.join(user_dir, 'test_tool')
      FileUtils.mkdir_p(tool_dir)

      File.write(File.join(tool_dir, '1.0.yaml'), <<~YAML)
        name: test_tool
        version: "1.0"
        profiles:
          - name: default
            platforms: [linux]
            shells: [bash]
      YAML

      File.write(File.join(tool_dir, '2.0.yaml'), <<~YAML)
        name: test_tool
        version: "2.0"
        profiles:
          - name: default
            platforms: [linux]
            shells: [bash]
      YAML
    end

    it 'returns best definition when no version specified' do
      allow(described_class).to receive(:search_paths).and_return([user_dir])

      metadata = described_class.find('test_tool')

      expect(metadata).to be_a(Ukiryu::Definition::DefinitionMetadata)
      expect(metadata.name).to eq('test_tool')
    end

    it 'returns specific version when requested' do
      allow(described_class).to receive(:search_paths).and_return([user_dir])

      metadata = described_class.find('test_tool', '2.0')

      expect(metadata).to be_a(Ukiryu::Definition::DefinitionMetadata)
      expect(metadata.version).to eq('2.0')
    end

    it 'returns nil for non-existent tool' do
      allow(described_class).to receive(:discover).and_return({})

      metadata = described_class.find('nonexistent')

      expect(metadata).to be_nil
    end

    it 'returns nil for non-existent version' do
      metadata1 = Ukiryu::Definition::DefinitionMetadata.new(
        name: 'test_tool',
        version: '1.0',
        path: File.join(user_dir, 'test_tool', '1.0.yaml'),
        source_type: :user
      )

      allow(described_class).to receive(:discover).and_return({
                                                                'test_tool' => [metadata1]
                                                              })

      metadata = described_class.find('test_tool', '99.0')

      expect(metadata).to be_nil
    end
  end

  describe '.available_tools' do
    it 'returns array of tool names' do
      allow(described_class).to receive(:discover).and_return({
                                                                'tool1' => [],
                                                                'tool2' => []
                                                              })

      tools = described_class.available_tools

      expect(tools).to eq(%w[tool1 tool2])
    end

    it 'returns empty array when no tools found' do
      allow(described_class).to receive(:discover).and_return({})

      tools = described_class.available_tools

      expect(tools).to eq([])
    end
  end

  describe '.definitions_for' do
    it 'returns definitions for a specific tool' do
      metadata1 = instance_double(Ukiryu::Definition::DefinitionMetadata, name: 'test')
      metadata2 = instance_double(Ukiryu::Definition::DefinitionMetadata, name: 'test')

      allow(described_class).to receive(:discover).and_return({
                                                                'test' => [metadata1, metadata2],
                                                                'other' => []
                                                              })

      definitions = described_class.definitions_for('test')

      expect(definitions).to eq([metadata1, metadata2])
    end

    it 'returns empty array for non-existent tool' do
      allow(described_class).to receive(:discover).and_return({})

      definitions = described_class.definitions_for('nonexistent')

      expect(definitions).to eq([])
    end
  end
end
