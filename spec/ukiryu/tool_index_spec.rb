# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::ToolIndex do
  # Use the same registry path as spec_helper to avoid path conflicts
  let(:registry_path) { File.expand_path('../../../register', __dir__) }

  before do
    # Reset the singleton before each test
    described_class.reset
  end

  after do
    # Clean up after tests
    described_class.reset
  end

  describe '.instance' do
    it 'returns the singleton instance' do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be_a(described_class)
      expect(instance1).to be(instance2) # Same object
    end

    it 'creates a new instance after reset' do
      instance1 = described_class.instance
      described_class.reset
      instance2 = described_class.instance

      expect(instance1).to be_a(described_class)
      expect(instance2).to be_a(described_class)
      expect(instance1).not_to be(instance2) # Different objects
    end
  end

  describe '.reset' do
    it 'clears the singleton instance' do
      instance1 = described_class.instance
      described_class.reset
      instance2 = described_class.instance

      expect(instance1).not_to be(instance2)
    end
  end

  describe '#initialize' do
    it 'creates a new index with a registry path' do
      index = described_class.new(registry_path: registry_path)

      expect(index.instance_variable_get(:@registry_path)).to eq(registry_path)
      expect(index.instance_variable_get(:@interface_to_tools)).to eq({})
      expect(index.instance_variable_get(:@built)).to be(false)
    end

    it 'uses the default registry path if none provided' do
      Ukiryu::Registry.default_registry_path = registry_path
      default_index = described_class.new

      expect(default_index.instance_variable_get(:@registry_path)).to eq(registry_path)
    end
  end

  describe '#find_by_interface' do
    context 'when registry path is nil and default is also nil' do
      it 'returns nil' do
        # Temporarily clear the default registry path
        original_path = Ukiryu::Registry.default_registry_path
        Ukiryu::Registry.default_registry_path = nil

        index = described_class.new(registry_path: nil)
        metadata = index.find_by_interface(:ping)

        expect(metadata).to be_nil

        # Restore the default registry path
        Ukiryu::Registry.default_registry_path = original_path
      end
    end

    context 'when interface does not exist' do
      it 'returns nil' do
        index = described_class.new(registry_path: '/nonexistent/path')
        metadata = index.find_by_interface(:nonexistent_interface)

        expect(metadata).to be_nil
      end
    end
  end

  describe '#all_tools' do
    context 'when registry path is nil and default is also nil' do
      it 'returns empty hash' do
        # Temporarily clear the default registry path
        original_path = Ukiryu::Registry.default_registry_path
        Ukiryu::Registry.default_registry_path = nil

        index = described_class.new(registry_path: nil)
        tools = index.all_tools

        expect(tools).to eq({})

        # Restore the default registry path
        Ukiryu::Registry.default_registry_path = original_path
      end
    end

    context 'when tools are found' do
      it 'returns a hash of interfaces to tool names' do
        # Skip if registry doesn't exist
        skip "Registry not found at #{registry_path}" unless Dir.exist?(registry_path)

        index = described_class.new(registry_path: registry_path)
        tools = index.all_tools

        expect(tools).to be_a(Hash)
        # The ping interface should be mapped to either ping_bsd or ping_gnu
        expect(tools.keys).to include(:ping)
      end
    end
  end

  describe '#registry_path=' do
    it 'updates the registry path' do
      index = described_class.new(registry_path: registry_path)
      new_path = '/new/path'
      index.registry_path = new_path

      expect(index.instance_variable_get(:@registry_path)).to eq(new_path)
    end

    it 'rebuilds the index when path changes' do
      index = described_class.new(registry_path: registry_path)

      # Build the index first
      index.all_tools if Dir.exist?(registry_path)
      index.instance_variable_get(:@built)

      # Change the path
      index.registry_path = '/new/path'

      # Index should be marked for rebuild
      expect(index.instance_variable_get(:@built)).to be(false)
      expect(index.instance_variable_get(:@interface_to_tools)).to eq({})
    end

    it 'does not rebuild if the path is the same' do
      # Skip if registry doesn't exist
      skip "Registry not found at #{registry_path}" unless Dir.exist?(registry_path)

      index = described_class.new(registry_path: registry_path)

      # Build the index first
      index.all_tools
      old_interface_to_tools = index.instance_variable_get(:@interface_to_tools).dup

      # Set the same path
      index.registry_path = registry_path

      # Index should still be built and unchanged
      expect(index.instance_variable_get(:@built)).to be(true)
      expect(index.instance_variable_get(:@interface_to_tools)).to eq(old_interface_to_tools)
    end
  end
end
