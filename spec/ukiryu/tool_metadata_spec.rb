# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::ToolMetadata do
  let(:registry_path) { File.expand_path('../../register', __dir__) }

  describe '#initialize' do
    it 'creates metadata with all attributes' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0',
        display_name: 'Test Tool',
        implements: :test_interface,
        homepage: 'https://example.com',
        description: 'A test tool',
        aliases: %w[test tst],
        tool_name: 'test_tool',
        registry_path: registry_path,
        default_command: :default
      )

      expect(metadata.name).to eq('test_tool')
      expect(metadata.version).to eq('1.0.0')
      expect(metadata.display_name).to eq('Test Tool')
      expect(metadata.implements).to eq(:test_interface)
      expect(metadata.homepage).to eq('https://example.com')
      expect(metadata.description).to eq('A test tool')
      expect(metadata.aliases).to eq(%w[test tst])
      expect(metadata.tool_name).to eq('test_tool')
      expect(metadata.registry_path).to eq(registry_path)
      expect(metadata.default_command).to eq(:default)
    end

    it 'creates metadata with required attributes only' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0'
      )

      expect(metadata.name).to eq('test_tool')
      expect(metadata.version).to eq('1.0.0')
      expect(metadata.display_name).to be_nil
      expect(metadata.implements).to be_nil
      expect(metadata.homepage).to be_nil
      expect(metadata.description).to be_nil
      expect(metadata.aliases).to eq([])
      expect(metadata.tool_name).to eq('test_tool')
      expect(metadata.registry_path).to be_nil
      # default_command falls back to name when not provided
      expect(metadata.default_command).to eq(:test_tool)
    end

    it 'uses name as tool_name when tool_name is not provided' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0'
      )

      expect(metadata.tool_name).to eq('test_tool')
    end

    it 'converts aliases to array' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0',
        aliases: 'single_alias'
      )

      expect(metadata.aliases).to eq(['single_alias'])
    end
  end

  describe '#implements?' do
    context 'when the tool implements the interface' do
      it 'returns true' do
        metadata = described_class.new(
          name: 'ping_tool',
          version: '1.0.0',
          implements: :ping
        )

        expect(metadata.implements?(:ping)).to be(true)
        expect(metadata.implements?('ping')).to be(true)
      end
    end

    context 'when the tool does not implement the interface' do
      it 'returns false' do
        metadata = described_class.new(
          name: 'other_tool',
          version: '1.0.0',
          implements: :other
        )

        expect(metadata.implements?(:ping)).to be(false)
      end
    end

    context 'when implements is nil' do
      it 'returns false' do
        metadata = described_class.new(
          name: 'test_tool',
          version: '1.0.0'
        )

        expect(metadata.implements?(:ping)).to be(false)
      end
    end
  end

  describe '#default_command' do
    it 'returns the default_command when set' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0',
        default_command: :custom_default
      )

      expect(metadata.default_command).to eq(:custom_default)
    end

    it 'falls back to implements when default_command is not set' do
      metadata = described_class.new(
        name: 'ping_tool',
        version: '1.0.0',
        implements: :ping
      )

      expect(metadata.default_command).to eq(:ping)
    end

    it 'falls back to name when neither default_command nor implements are set' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0'
      )

      expect(metadata.default_command).to eq(:test_tool)
    end

    it 'prioritizes default_command over implements' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0',
        implements: :implements_value,
        default_command: :default_value
      )

      expect(metadata.default_command).to eq(:default_value)
    end
  end

  describe '#to_s' do
    it 'returns a string representation with display_name' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0',
        display_name: 'Test Tool'
      )

      expect(metadata.to_s).to eq('Test Tool v1.0.0')
    end

    it 'returns a string representation with name when display_name is nil' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0'
      )

      expect(metadata.to_s).to eq('test_tool v1.0.0')
    end
  end

  describe '#inspect' do
    it 'returns a detailed inspection string' do
      metadata = described_class.new(
        name: 'test_tool',
        version: '1.0.0',
        implements: :test_interface
      )

      inspection = metadata.inspect
      expect(inspection).to include('#<Ukiryu::ToolMetadata')
      # inspect uses Ruby's .inspect which produces quoted strings
      expect(inspection).to include('name="test_tool"')
      expect(inspection).to include('version="1.0.0"')
      expect(inspection).to include('implements=:test_interface')
    end
  end

  describe '.from_hash' do
    let(:hash) do
      {
        'version' => '1.0.0',
        'display_name' => 'Test Tool',
        'implements' => 'test_interface',
        'homepage' => 'https://example.com',
        'description' => 'A test tool',
        'aliases' => %w[test tst],
        'default_command' => 'custom_default'
      }
    end

    it 'creates metadata from a hash' do
      metadata = described_class.from_hash(hash, tool_name: 'test_tool', registry_path: registry_path)

      expect(metadata.name).to eq('test_tool')
      expect(metadata.version).to eq('1.0.0')
      expect(metadata.display_name).to eq('Test Tool')
      expect(metadata.implements).to eq(:test_interface)
      expect(metadata.homepage).to eq('https://example.com')
      expect(metadata.description).to eq('A test tool')
      expect(metadata.aliases).to eq(%w[test tst])
      expect(metadata.default_command).to eq('custom_default')
      expect(metadata.tool_name).to eq('test_tool')
      expect(metadata.registry_path).to eq(registry_path)
    end

    it 'handles nil values in the hash' do
      hash = {
        'version' => '1.0.0',
        'implements' => nil,
        'aliases' => nil
      }

      metadata = described_class.from_hash(hash, tool_name: 'test_tool', registry_path: registry_path)

      expect(metadata.implements).to be_nil
      expect(metadata.aliases).to eq([])
    end

    it 'converts implements string to symbol' do
      hash = {
        'version' => '1.0.0',
        'implements' => 'ping'
      }

      metadata = described_class.from_hash(hash, tool_name: 'ping_tool', registry_path: registry_path)

      expect(metadata.implements).to eq(:ping)
    end
  end

  describe 'integration with Registry' do
    it 'can load metadata for a real tool' do
      metadata = Ukiryu::Registry.load_tool_metadata(:ping, registry_path: registry_path)

      expect(metadata).to be_a(described_class)
      expect(metadata.name).to be_a(String)
      expect(metadata.version).to be_a(String)
    end

    it 'can find tools by interface' do
      # Ping tool implements the 'ping' interface
      metadata = Ukiryu::Registry.load_tool_metadata(:ping, registry_path: registry_path)

      expect(metadata).to be_a(described_class)
      expect(metadata.implements).to eq(:ping)
    end
  end
end
