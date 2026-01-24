# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Models::Routing do
  describe '#initialize' do
    it 'creates an empty routing table by default' do
      routing = described_class.new
      expect(routing.empty?).to be true
      expect(routing.size).to eq(0)
    end

    it 'creates a routing table from a hash' do
      routing = described_class.new({ 'remote' => 'git-remote', 'branch' => 'git-branch' })
      expect(routing.size).to eq(2)
      expect(routing.keys).to eq(%w[branch remote])
    end

    it 'creates a routing table with a parent' do
      parent = described_class.new({ 'root' => 'git' })
      child = described_class.new({ 'add' => 'action' }, parent: parent)
      expect(child.parent).to eq(parent)
    end
  end

  describe '#resolve' do
    it 'resolves a command name to its executable target' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.resolve('remote')).to eq('git-remote')
      expect(routing.resolve(:remote)).to eq('git-remote')
    end

    it 'returns nil for unknown commands' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.resolve('unknown')).to be_nil
    end

    it 'resolves through parent routing table' do
      parent = described_class.new({ 'root' => 'git' })
      child = described_class.new({ 'add' => 'action' }, parent: parent)
      expect(child.resolve('root')).to eq('git')
      expect(child.resolve('add')).to eq('action')
    end
  end

  describe '#resolve_path' do
    it 'resolves a single-level path' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.resolve_path(['remote'])).to eq(['git-remote'])
    end

    it 'resolves a multi-level path' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      child = routing.child('remote')
      child.merge!({ 'add' => 'action', 'remove' => 'action' })
      expect(routing.resolve_path(%w[remote add])).to eq(%w[git-remote action])
      expect(routing.resolve_path(%w[remote remove])).to eq(%w[git-remote action])
    end

    it 'returns empty array for empty path' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.resolve_path([])).to eq([])
    end

    it 'returns empty array for unknown first-level command' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.resolve_path(%w[unknown add])).to eq([])
    end
  end

  describe '#include?' do
    it 'returns true for existing commands' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.include?('remote')).to be true
      expect(routing.include?(:remote)).to be true
    end

    it 'returns false for non-existing commands' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.include?('unknown')).to be false
    end

    it 'checks parent routing table' do
      parent = described_class.new({ 'root' => 'git' })
      child = described_class.new({ 'add' => 'action' }, parent: parent)
      expect(child.include?('root')).to be true
      expect(child.include?('add')).to be true
      expect(child.include?('unknown')).to be false
    end
  end

  describe '#child' do
    it 'creates or returns a child routing table' do
      routing = described_class.new
      child = routing.child('remote')
      expect(child).to be_a(described_class)
      expect(child.parent).to eq(routing)
      expect(routing.child('remote')).to eq(child) # Same instance
    end

    it 'creates different children for different commands' do
      routing = described_class.new
      child1 = routing.child('remote')
      child2 = routing.child('branch')
      expect(child1).not_to eq(child2)
    end
  end

  describe '#merge!' do
    it 'merges a hash into the routing table' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      result = routing.merge!({ 'branch' => 'git-branch', 'stash' => 'git-stash' })
      expect(result).to eq(routing) # Returns self
      expect(routing.size).to eq(3)
      expect(routing.keys.sort).to eq(%w[branch remote stash])
    end

    it 'symbolizes keys when merging' do
      routing = described_class.new
      routing.merge!({ 'remote' => 'git-remote' })
      expect(routing.resolve('remote')).to eq('git-remote')
      expect(routing.resolve(:remote)).to eq('git-remote')
    end
  end

  describe '#keys' do
    it 'returns sorted command names' do
      routing = described_class.new({ 'remote' => 'git-remote', 'branch' => 'git-branch', 'stash' => 'git-stash' })
      expect(routing.keys).to eq(%w[branch remote stash])
    end

    it 'returns empty array for empty routing table' do
      routing = described_class.new
      expect(routing.keys).to eq([])
    end
  end

  describe '#empty?' do
    it 'returns true for empty routing table' do
      routing = described_class.new
      expect(routing.empty?).to be true
    end

    it 'returns false for non-empty routing table' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.empty?).to be false
    end
  end

  describe '#size' do
    it 'returns the number of routing entries' do
      routing = described_class.new({ 'remote' => 'git-remote', 'branch' => 'git-branch' })
      expect(routing.size).to eq(2)
    end
  end

  describe '#to_h' do
    it 'converts routing table to hash with string keys' do
      routing = described_class.new({ 'remote' => 'git-remote', 'branch' => 'git-branch' })
      hash = routing.to_h
      expect(hash).to eq({ 'remote' => 'git-remote', 'branch' => 'git-branch' })
      expect(hash.keys).to all(be_a(String))
    end
  end

  describe '#circular?' do
    it 'returns false for routing without parent' do
      routing = described_class.new
      expect(routing.circular?).to be false
    end

    it 'returns false for non-circular parent chain' do
      parent = described_class.new
      child = described_class.new({}, parent: parent)
      grandchild = described_class.new({}, parent: child)
      expect(grandchild.circular?).to be false
    end

    it 'returns true for circular references' do
      parent = described_class.new
      child = described_class.new({}, parent: parent)
      # Simulate circular reference
      parent.instance_variable_set(:@parent, child)
      expect(child.circular?).to be true
    end
  end

  describe '#inspect' do
    it 'returns debug-friendly string representation' do
      routing = described_class.new({ 'remote' => 'git-remote' })
      expect(routing.inspect).to match(/#<Ukiryu::Models::Routing/)
      expect(routing.inspect).to match(/:remote/)
    end

    it 'includes parent info when parent exists' do
      parent = described_class.new
      child = described_class.new({}, parent: parent)
      expect(child.inspect).to match(/\(parent:/)
    end
  end

  describe '#to_s' do
    it 'returns routing table as formatted string' do
      routing = described_class.new({ 'remote' => 'git-remote', 'branch' => 'git-branch' })
      string = routing.to_s
      expect(string).to include('remote => git-remote')
      expect(string).to include('branch => git-branch')
    end

    it 'returns (empty) for empty routing table' do
      routing = described_class.new
      expect(routing.to_s).to eq('(empty)')
    end
  end

  describe 'multi-level hierarchies' do
    it 'supports three-level hierarchies' do
      root = described_class.new({ 'git' => 'git' })
      level1 = root.child('git')
      level1.merge!({ 'remote' => 'git-remote' })
      level2 = level1.child('remote')
      level2.merge!({ 'add' => 'action' })

      expect(root.resolve_path(%w[git remote add])).to eq(%w[git git-remote action])
    end

    it 'supports branching hierarchies' do
      root = described_class.new({ 'git' => 'git' })
      level1 = root.child('git')
      level1.merge!({ 'remote' => 'git-remote', 'branch' => 'git-branch' })

      remote_child = level1.child('remote')
      remote_child.merge!({ 'add' => 'add-action', 'remove' => 'remove-action' })

      branch_child = level1.child('branch')
      branch_child.merge!({ 'list' => 'list-action', 'delete' => 'delete-action' })

      expect(root.resolve_path(%w[git remote add])).to eq(%w[git git-remote add-action])
      expect(root.resolve_path(%w[git branch delete])).to eq(%w[git git-branch delete-action])
    end
  end
end
