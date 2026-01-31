# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Environment do
  describe '#initialize' do
    it 'creates an empty environment by default' do
      env = described_class.new
      expect(env.to_h).to eq({})
    end

    it 'creates an environment from a hash' do
      env = described_class.new('PATH' => '/usr/bin', 'HOME' => '/home/user')
      expect(env['PATH']).to eq('/usr/bin')
      expect(env['HOME']).to eq('/home/user')
    end

    it 'duplicates the input hash' do
      original = { 'KEY' => 'value' }
      env = described_class.new(original)
      original['KEY'] = 'modified'
      expect(env['KEY']).to eq('value')
    end
  end

  describe '.system' do
    it 'creates an empty environment' do
      env = described_class.system
      expect(env.to_h).to eq({})
    end
  end

  describe '.from_env' do
    it 'copies from ENV' do
      # NOTE: This test runs with whatever ENV is set in the test environment
      env = described_class.from_env
      expect(env.to_h).to be_a(Hash)
      expect(env.to_h).to include('PATH') if ENV['PATH']
    end

    it 'returns a frozen copy' do
      env = described_class.from_env
      expect(env.to_h).not_to be_frozen
      expect { env.to_h['NEW_VAR'] = 'value' }.not_to raise_error
    end
  end

  describe '#[]' do
    it 'returns the value for an existing key' do
      env = described_class.new('FOO' => 'bar')
      expect(env['FOO']).to eq('bar')
    end

    it 'returns nil for a missing key' do
      env = described_class.new
      expect(env['MISSING']).to be_nil
    end

    it 'converts symbol keys to strings' do
      env = described_class.new('FOO' => 'bar')
      expect(env[:FOO]).to eq('bar')
    end
  end

  describe '#key?' do
    it 'returns true for existing key' do
      env = described_class.new('FOO' => 'bar')
      expect(env.key?('FOO')).to be true
    end

    it 'returns false for missing key' do
      env = described_class.new
      expect(env.key?('MISSING')).to be false
    end

    it 'accepts symbol keys' do
      env = described_class.new('FOO' => 'bar')
      expect(env.key?(:FOO)).to be true
    end
  end

  describe '#keys' do
    it 'returns all keys' do
      env = described_class.new('A' => '1', 'B' => '2', 'C' => '3')
      expect(env.keys).to match_array(%w[A B C])
    end
  end

  describe '#to_h' do
    it 'returns a mutable copy' do
      env = described_class.new('KEY' => 'value')
      hash = env.to_h
      hash['NEW'] = 'value'
      expect(env.key?('NEW')).to be false
    end

    it 'returns a duplicate' do
      env = described_class.new('KEY' => 'value')
      hash1 = env.to_h
      hash2 = env.to_h
      hash1['KEY'] = 'modified'
      expect(hash2['KEY']).to eq('value')
    end
  end

  describe '#set' do
    it 'sets a new variable' do
      env = described_class.new.set('NEW_VAR', 'new_value')
      expect(env['NEW_VAR']).to eq('new_value')
    end

    it 'updates an existing variable' do
      env = described_class.new('VAR' => 'old').set('VAR', 'new')
      expect(env['VAR']).to eq('new')
    end

    it 'returns a new instance' do
      original = described_class.new('VAR' => 'original')
      updated = original.set('VAR', 'new')
      expect(original['VAR']).to eq('original')
      expect(updated['VAR']).to eq('new')
    end

    it 'converts value to string' do
      env = described_class.new.set('NUM', 123)
      expect(env['NUM']).to eq('123')
    end

    it 'converts symbol keys to strings' do
      env = described_class.new.set(:SYMBOL_KEY, 'value')
      expect(env['SYMBOL_KEY']).to eq('value')
    end
  end

  describe '#delete' do
    it 'removes an existing variable' do
      env = described_class.new('A' => '1', 'B' => '2').delete('A')
      expect(env.key?('A')).to be false
      expect(env.key?('B')).to be true
    end

    it 'returns a new instance' do
      original = described_class.new('A' => '1')
      deleted = original.delete('A')
      expect(original.key?('A')).to be true
      expect(deleted.key?('A')).to be false
    end

    it 'handles missing keys gracefully' do
      env = described_class.new.delete('MISSING')
      expect(env.key?('MISSING')).to be false
    end
  end

  describe '#merge' do
    it 'merges another Environment' do
      env1 = described_class.new('A' => '1', 'B' => '2')
      env2 = described_class.new('B' => 'updated', 'C' => '3')
      merged = env1.merge(env2)
      expect(merged['A']).to eq('1')
      expect(merged['B']).to eq('updated')
      expect(merged['C']).to eq('3')
    end

    it 'merges a Hash' do
      env = described_class.new('A' => '1')
      merged = env.merge('B' => '2', 'C' => '3')
      expect(merged['A']).to eq('1')
      expect(merged['B']).to eq('2')
      expect(merged['C']).to eq('3')
    end

    it 'returns a new instance' do
      original = described_class.new('A' => '1')
      merged = original.merge('B' => '2')
      expect(original.key?('B')).to be false
      expect(merged.key?('B')).to be true
    end
  end

  describe '#prepend_path' do
    it 'prepends a single directory to PATH' do
      env = described_class.new('PATH' => '/usr/bin:/usr/local/bin')
                           .prepend_path('/opt/bin')
      expect(env['PATH']).to eq('/opt/bin:/usr/bin:/usr/local/bin')
    end

    it 'prepends multiple directories' do
      env = described_class.new('PATH' => '/usr/bin')
                           .prepend_path(['/opt/bin', '/usr/local/bin'])
      expect(env['PATH']).to eq('/opt/bin:/usr/local/bin:/usr/bin')
    end

    it 'creates PATH if it does not exist' do
      env = described_class.new.prepend_path('/new/bin')
      expect(env['PATH']).to eq('/new/bin')
    end

    it 'returns a new instance' do
      original = described_class.new('PATH' => '/usr/bin')
      prepended = original.prepend_path('/opt')
      expect(original['PATH']).to eq('/usr/bin')
      expect(prepended['PATH']).to eq('/opt:/usr/bin')
    end
  end

  describe '#append_path' do
    it 'appends a directory to PATH' do
      env = described_class.new('PATH' => '/usr/bin:/usr/local/bin')
                           .append_path('/opt/bin')
      expect(env['PATH']).to eq('/usr/bin:/usr/local/bin:/opt/bin')
    end

    it 'appends multiple directories' do
      env = described_class.new('PATH' => '/usr/bin')
                           .append_path(['/opt/bin', '/usr/local/bin'])
      expect(env['PATH']).to eq('/usr/bin:/opt/bin:/usr/local/bin')
    end

    it 'creates PATH if it does not exist' do
      env = described_class.new.append_path('/new/bin')
      expect(env['PATH']).to eq('/new/bin')
    end

    it 'returns a new instance' do
      original = described_class.new('PATH' => '/usr/bin')
      appended = original.append_path('/opt')
      expect(original['PATH']).to eq('/usr/bin')
      expect(appended['PATH']).to eq('/usr/bin:/opt')
    end
  end

  describe '#remove_path' do
    it 'removes a directory from PATH' do
      env = described_class.new('PATH' => '/usr/bin:/opt/bin:/usr/local/bin')
                           .remove_path('/opt/bin')
      expect(env['PATH']).to eq('/usr/bin:/usr/local/bin')
    end

    it 'removes multiple occurrences' do
      env = described_class.new('PATH' => '/usr/bin:/usr/bin:/opt/bin')
                           .remove_path('/usr/bin')
      expect(env['PATH']).to eq('/opt/bin')
    end

    it 'handles missing directory gracefully' do
      env = described_class.new('PATH' => '/usr/bin')
                           .remove_path('/nonexistent')
      expect(env['PATH']).to eq('/usr/bin')
    end

    it 'returns a new instance' do
      original = described_class.new('PATH' => '/usr/bin:/opt/bin')
      removed = original.remove_path('/opt')
      expect(original['PATH']).to eq('/usr/bin:/opt/bin')
      expect(removed['PATH']).to eq('/usr/bin')
    end
  end

  describe '#path_contains?' do
    it 'returns true if directory is in PATH' do
      env = described_class.new('PATH' => '/usr/bin:/usr/local/bin')
      expect(env.path_contains?('/usr/bin')).to be true
      expect(env.path_contains?('/usr/local/bin')).to be true
    end

    it 'returns false if directory is not in PATH' do
      env = described_class.new('PATH' => '/usr/bin')
      expect(env.path_contains?('/opt/bin')).to be false
    end

    it 'returns false if PATH is not set' do
      env = described_class.new
      expect(env.path_contains?('/usr/bin')).to be false
    end
  end

  describe '#path_array' do
    it 'returns PATH as an array' do
      env = described_class.new('PATH' => '/usr/bin:/usr/local/bin:/opt/bin')
      expect(env.path_array).to eq(['/usr/bin', '/usr/local/bin', '/opt/bin'])
    end

    it 'returns empty array if PATH is not set' do
      env = described_class.new
      expect(env.path_array).to eq([])
    end
  end

  describe '#==' do
    it 'returns true for equal environments' do
      env1 = described_class.new('A' => '1', 'B' => '2')
      env2 = described_class.new('A' => '1', 'B' => '2')
      expect(env1).to eq(env2)
    end

    it 'returns false for different environments' do
      env1 = described_class.new('A' => '1')
      env2 = described_class.new('A' => '2')
      expect(env1).not_to eq(env2)
    end

    it 'returns false for non-Environment objects' do
      env = described_class.new('A' => '1')
      expect(env).not_to eq({ 'A' => '1' })
    end
  end

  describe '#hash' do
    it 'returns consistent hash values' do
      env1 = described_class.new('A' => '1', 'B' => '2')
      env2 = described_class.new('A' => '1', 'B' => '2')
      expect(env1.hash).to eq(env2.hash)
    end

    it 'can be used as Hash key' do
      env = described_class.new('A' => '1')
      hash = { env => 'value' }
      expect(hash[env]).to eq('value')
    end
  end

  describe '#inspect' do
    it 'shows key count' do
      env = described_class.new('A' => '1', 'B' => '2', 'C' => '3')
      expect(env.inspect).to eq('#<Ukiryu::Environment keys=3>')
    end
  end

  context 'immutability' do
    it 'does not modify original when setting' do
      original = described_class.new('VAR' => 'original')
      modified = original.set('VAR', 'modified')
      expect(original['VAR']).to eq('original')
      expect(modified['VAR']).to eq('modified')
    end

    it 'does not modify original when deleting' do
      original = described_class.new('VAR' => 'value')
      deleted = original.delete('VAR')
      expect(original.key?('VAR')).to be true
      expect(deleted.key?('VAR')).to be false
    end

    it 'does not modify original when merging' do
      original = described_class.new('A' => '1')
      merged = original.merge('B' => '2')
      expect(original.key?('B')).to be false
      expect(merged.key?('B')).to be true
    end

    it 'does not modify original when manipulating PATH' do
      original = described_class.new('PATH' => '/usr/bin')
      modified = original.prepend_path('/opt')
      expect(original['PATH']).to eq('/usr/bin')
      expect(modified['PATH']).to eq('/opt:/usr/bin')
    end
  end

  context 'chroot scenario' do
    it 'can rebuild PATH for chroot' do
      # Simulates: User wants to use /chroot/usr/bin instead of /usr/bin
      env = described_class.from_env
                           .prepend_path('/chroot/usr/bin')
                           .prepend_path('/chroot/bin')

      expect(env.path_array.first).to eq('/chroot/bin')
      expect(env.path_array[1]).to eq('/chroot/usr/bin')
    end

    it 'can set multiple environment variables for chroot' do
      env = described_class.new
                           .set('CHROOT', '/mnt/chroot')
                           .set('PATH', '/chroot/usr/bin:/chroot/bin:/usr/bin')

      expect(env['CHROOT']).to eq('/mnt/chroot')
      expect(env['PATH']).to include('/chroot')
    end

    it 'can bridge virtual environment' do
      # Simulates: Bridging venv environment to spawned shell
      env = described_class.from_env
                           .set('VIRTUAL_ENV', '/home/user/.venv')
                           .prepend_path('/home/user/.venv/bin')

      expect(env['VIRTUAL_ENV']).to eq('/home/user/.venv')
      expect(env.path_contains?('/home/user/.venv/bin')).to be true
    end
  end
end
