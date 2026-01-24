# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::VersionResolver do
  describe '.parse_constraint' do
    it 'parses exact version constraint' do
      constraints = described_class.parse_constraint('1.0')
      expect(constraints).to be_an(Array)
      expect(constraints.first.operator).to eq(:==)
      expect(constraints.first.version).to eq('1.0')
    end

    it 'parses minimum version constraint' do
      constraints = described_class.parse_constraint('>= 1.0')
      expect(constraints.first.operator).to eq(:>=)
      expect(constraints.first.version).to eq('1.0')
    end

    it 'parses maximum version constraint' do
      constraints = described_class.parse_constraint('<= 2.0')
      expect(constraints.first.operator).to eq(:<=)
      expect(constraints.first.version).to eq('2.0')
    end

    it 'parses pessimistic version constraint' do
      constraints = described_class.parse_constraint('~> 1.2')
      expect(constraints.first.operator).to eq('~>'.to_sym)
      expect(constraints.first.version).to eq('1.2')
    end

    it 'parses compound constraints' do
      constraints = described_class.parse_constraint('>= 1.0, < 2.0')
      expect(constraints.length).to eq(2)
      expect(constraints[0].operator).to eq(:>=)
      expect(constraints[1].operator).to eq(:<)
    end
  end

  describe '.satisfies?' do
    it 'returns true for exact match' do
      expect(described_class.satisfies?('1.0', '1.0')).to be true
      expect(described_class.satisfies?('1.0', '1.1')).to be false
    end

    it 'returns true for minimum version constraint' do
      expect(described_class.satisfies?('1.5', '>= 1.0')).to be true
      expect(described_class.satisfies?('0.9', '>= 1.0')).to be false
    end

    it 'returns true for maximum version constraint' do
      expect(described_class.satisfies?('1.5', '<= 2.0')).to be true
      expect(described_class.satisfies?('2.1', '<= 2.0')).to be false
    end

    it 'returns true for pessimistic version constraint' do
      expect(described_class.satisfies?('1.2.5', '~> 1.2')).to be true
      expect(described_class.satisfies?('1.3.0', '~> 1.2')).to be false
      expect(described_class.satisfies?('0.9.0', '~> 1.2')).to be false
    end

    it 'returns true for compound constraints' do
      expect(described_class.satisfies?('1.5', '>= 1.0, < 2.0')).to be true
      expect(described_class.satisfies?('2.0', '>= 1.0, < 2.0')).to be false
    end
  end

  describe '.resolve' do
    it 'returns highest matching version' do
      versions = ['1.0', '1.2', '2.0', '0.9']
      result = described_class.resolve('>= 1.0', versions)
      expect(result).to eq('2.0')
    end

    it 'returns nil when no versions match' do
      versions = ['1.0', '1.2', '2.0']
      result = described_class.resolve('> 2.0', versions)
      expect(result).to be_nil
    end

    it 'handles exact version constraint' do
      versions = ['1.0', '1.2', '2.0']
      result = described_class.resolve('1.2', versions)
      expect(result).to eq('1.2')
    end

    it 'handles pessimistic version constraint' do
      versions = ['1.2.0', '1.2.5', '1.3.0', '2.0.0']
      result = described_class.resolve('~> 1.2', versions)
      expect(result).to eq('1.2.5')
    end

    it 'returns nil for empty versions array' do
      result = described_class.resolve('1.0', [])
      expect(result).to be_nil
    end
  end

  describe '.compare_versions' do
    it 'compares versions correctly' do
      expect(described_class.compare_versions('1.0', '2.0')).to be < 0
      expect(described_class.compare_versions('2.0', '1.0')).to be > 0
      expect(described_class.compare_versions('1.0', '1.0')).to eq(0)
    end

    it 'compares version arrays' do
      v1 = [1, 2, 0]
      v2 = [1, 2, 5]
      expect(described_class.compare_versions(v1, v2)).to be < 0
    end

    it 'handles different length versions' do
      expect(described_class.compare_versions('1.0', '1.0.1')).to be < 0
      expect(described_class.compare_versions('1.0.0', '1.0')).to eq(0)
    end
  end

  describe '.parse_version' do
    it 'parses version string into components' do
      result = described_class.parse_version('1.2.3')
      expect(result).to eq([1, 2, 3])
    end

    it 'handles two-part versions' do
      result = described_class.parse_version('1.2')
      expect(result).to eq([1, 2])
    end

    it 'handles single-part versions' do
      result = described_class.parse_version('1')
      expect(result).to eq([1])
    end
  end

  describe '.latest' do
    it 'returns highest version from list' do
      versions = ['1.0', '1.2', '2.0', '0.9']
      expect(described_class.latest(versions)).to eq('2.0')
    end

    it 'returns nil for empty list' do
      expect(described_class.latest([])).to be_nil
    end
  end

  describe '.pessimistic_range' do
    it 'returns range for pessimistic constraint' do
      min, max = described_class.pessimistic_range('1.2')
      expect(min).to eq('1.2')
      expect(max).to eq('1.3')
    end
  end
end
