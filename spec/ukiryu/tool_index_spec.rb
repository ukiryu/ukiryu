# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::ToolIndex do
  # Use register path from environment variable
  let(:register_path) { ENV['UKIRYU_REGISTER'] }

  before do
    # Reset the singleton before each test
    described_class.reset
    skip 'Set UKIRYU_REGISTER environment variable for this test' unless register_path && Dir.exist?(register_path)
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
    it 'creates a new index with a register path' do
      index = described_class.new(register_path: register_path)

      expect(index.instance_variable_get(:@register_path)).to eq(register_path)
      expect(index.instance_variable_get(:@interface_to_tools)).to eq({})
      expect(index.instance_variable_get(:@built)).to be(false)
    end

    it 'uses the default register path if none provided' do
      Ukiryu::Register.default_register_path = register_path
      default_index = described_class.new

      expect(default_index.instance_variable_get(:@register_path)).to eq(register_path)
    end
  end

  describe '#find_by_interface' do
    context 'when register path is nil and default is also nil' do
      it 'returns nil' do
        # Temporarily clear the default register path
        original_path = Ukiryu::Register.default_register_path
        Ukiryu::Register.default_register_path = nil

        index = described_class.new(register_path: nil)
        metadata = index.find_by_interface(:ping)

        expect(metadata).to be_nil

        # Restore the default register path
        Ukiryu::Register.default_register_path = original_path
      end
    end

    context 'when interface does not exist' do
      it 'returns nil' do
        index = described_class.new(register_path: '/nonexistent/path')
        metadata = index.find_by_interface(:nonexistent_interface)

        expect(metadata).to be_nil
      end
    end
  end

  describe '#all_tools' do
    context 'when register path is nil and default is also nil' do
      it 'returns empty hash' do
        # Temporarily clear the default register path
        original_path = Ukiryu::Register.default_register_path
        Ukiryu::Register.default_register_path = nil

        index = described_class.new(register_path: nil)
        tools = index.all_tools

        expect(tools).to eq({})

        # Restore the default register path
        Ukiryu::Register.default_register_path = original_path
      end
    end

    context 'when tools are found' do
      it 'returns a hash of interfaces to tool names' do
        # Skip if register doesn't exist
        skip "Register not found at #{register_path}" unless Dir.exist?(register_path)

        index = described_class.new(register_path: register_path)
        tools = index.all_tools

        expect(tools).to be_a(Hash)
        # The ping interface should be mapped to either ping_bsd or ping_gnu
        expect(tools.keys).to include(:ping)
      end
    end
  end

  describe '#register_path=' do
    it 'updates the register path' do
      index = described_class.new(register_path: register_path)
      new_path = '/new/path'
      index.register_path = new_path

      expect(index.instance_variable_get(:@register_path)).to eq(new_path)
    end

    it 'rebuilds the index when path changes' do
      index = described_class.new(register_path: register_path)

      # Build the index first
      index.all_tools if Dir.exist?(register_path)
      index.instance_variable_get(:@built)

      # Change the path
      index.register_path = '/new/path'

      # Index should be marked for rebuild
      expect(index.instance_variable_get(:@built)).to be(false)
      expect(index.instance_variable_get(:@interface_to_tools)).to eq({})
    end

    it 'does not rebuild if the path is the same' do
      # Skip if register doesn't exist
      skip "Register not found at #{register_path}" unless Dir.exist?(register_path)

      index = described_class.new(register_path: register_path)

      # Build the index first
      index.all_tools
      old_interface_to_tools = index.instance_variable_get(:@interface_to_tools).dup

      # Set the same path
      index.register_path = register_path

      # Index should still be built and unchanged
      expect(index.instance_variable_get(:@built)).to be(true)
      expect(index.instance_variable_get(:@interface_to_tools)).to eq(old_interface_to_tools)
    end
  end
end
