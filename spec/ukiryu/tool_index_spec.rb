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
      it 'returns nil when register cannot be found' do
        # This test verifies behavior when no register is available
        # In the new architecture, Register will always try to discover a register
        # So this test now verifies that when explicitly given a nonexistent path,
        # the find_by_interface returns nil

        # Create an index with an explicit nonexistent path
        index = described_class.new(register_path: '/nonexistent/register/path')
        metadata = index.find_by_interface(:ping)

        expect(metadata).to be_nil
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
      it 'returns empty hash when register cannot be found' do
        # Create an index with an explicit nonexistent path
        index = described_class.new(register_path: '/nonexistent/register/path')
        tools = index.all_tools

        expect(tools).to eq({})
      end
    end

    context 'when tools are found' do
      it 'returns a hash of interfaces to tool names' do
        # Skip if register doesn't exist
        skip "Register not found at #{register_path}" unless Dir.exist?(register_path)

        index = described_class.new(register_path: register_path)
        tools = index.all_tools

        expect(tools).to be_a(Hash)
        # With unified interface architecture, ping is exposed as :ping (not :ping/1.0 or :ping_bsd/1.0)
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

  describe '#select_latest_version_by_content' do
    # Make private method accessible
    before { Ukiryu::ToolIndex.send(:public, :select_latest_version_by_content) }

    let(:temp_dir) { Dir.mktmpdir('ukiryu_version_test') }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'selects version from YAML content, not filename' do
      # Create two files where filename and content version are SWAPPED
      # File named "9.5.yaml" but contains version: '10.0'
      # File named "10.0.yaml" but contains version: '9.5'
      file_nine = File.join(temp_dir, '9.5.yaml')
      file_ten = File.join(temp_dir, '10.0.yaml')

      File.write(file_nine, "---\nversion: '10.0'\nname: test\n")
      File.write(file_ten, "---\nversion: '9.5'\nname: test\n")

      index = described_class.new(register_path: '/dummy')
      result = index.select_latest_version_by_content([file_nine, file_ten])

      # Should return content of file with version 10.0 (file_nine),
      # NOT the file named "10.0.yaml" (file_ten)
      expect(result).to include("version: '10.0'")
    end

    it 'selects the file with highest version from content' do
      file1 = File.join(temp_dir, '1.0.yaml')
      file2 = File.join(temp_dir, '2.0.yaml')
      file3 = File.join(temp_dir, '3.0.yaml')

      File.write(file1, "---\nversion: '1.0'\nname: test\n")
      File.write(file2, "---\nversion: '2.0'\nname: test\n")
      File.write(file3, "---\nversion: '3.0'\nname: test\n")

      index = described_class.new(register_path: '/dummy')
      result = index.select_latest_version_by_content([file1, file2, file3])

      expect(result).to include("version: '3.0'")
    end

    it 'handles Ghostscript 10.0 vs 9.5 case correctly' do
      # This is the real-world case that caused the bug
      file_ten = File.join(temp_dir, '10.0.yaml')
      file_nine = File.join(temp_dir, '9.5.yaml')

      File.write(file_ten, "---\nversion: '10.0'\nname: ghostscript\nimplements: ghostscript/1.0\n")
      File.write(file_nine, "---\nversion: '9.5'\nname: ghostscript\nimplements: ghostscript/1.0\n")

      index = described_class.new(register_path: '/dummy')
      result = index.select_latest_version_by_content([file_nine, file_ten])

      expect(result).to include("version: '10.0'")
    end

    it 'returns nil for empty file list' do
      index = described_class.new(register_path: '/dummy')
      expect(index.select_latest_version_by_content([])).to be_nil
    end

    it 'returns content of single file' do
      file = File.join(temp_dir, '1.0.yaml')
      File.write(file, "---\nversion: '1.0'\nname: test\n")

      index = described_class.new(register_path: '/dummy')
      result = index.select_latest_version_by_content([file])

      expect(result).to include("version: '1.0'")
    end

    it 'skips files without version field' do
      file_with_version = File.join(temp_dir, 'with_version.yaml')
      file_without_version = File.join(temp_dir, 'no_version.yaml')

      File.write(file_with_version, "---\nversion: '2.0'\nname: test\n")
      File.write(file_without_version, "---\nname: test\n") # No version field

      index = described_class.new(register_path: '/dummy')
      result = index.select_latest_version_by_content([file_with_version, file_without_version])

      expect(result).to include("version: '2.0'")
    end

    it 'skips files that cannot be parsed' do
      valid_file = File.join(temp_dir, 'valid.yaml')
      invalid_file = File.join(temp_dir, 'invalid.yaml')

      File.write(valid_file, "---\nversion: '1.0'\nname: test\n")
      File.write(invalid_file, 'this is not valid yaml [[')

      index = described_class.new(register_path: '/dummy')
      result = index.select_latest_version_by_content([valid_file, invalid_file])

      expect(result).to include("version: '1.0'")
    end
  end
end
