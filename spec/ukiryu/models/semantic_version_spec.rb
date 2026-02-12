# frozen_string_literal: true

require 'spec_helper'
require 'ukiryu/models/semantic_version'

RSpec.describe Ukiryu::Models::SemanticVersion do
  describe '.parse' do
    it 'parses simple version' do
      expect(described_class.parse('10.0')).to eq([10, 0])
    end

    it 'parses three-part version' do
      expect(described_class.parse('1.2.3')).to eq([1, 2, 3])
    end

    it 'parses single number version' do
      expect(described_class.parse('5')).to eq([5])
    end

    it 'handles nil' do
      expect(described_class.parse(nil)).to eq([0])
    end

    it 'handles empty string' do
      expect(described_class.parse('')).to eq([0])
    end

    it 'handles non-numeric parts as 0' do
      expect(described_class.parse('1.alpha.3')).to eq([1, 0, 3])
    end
  end

  describe '.compare' do
    it 'returns 1 when first version is greater' do
      expect(described_class.compare('10.0', '9.5')).to eq(1)
    end

    it 'returns -1 when first version is lesser' do
      expect(described_class.compare('9.5', '10.0')).to eq(-1)
    end

    it 'returns 0 when versions are equal' do
      expect(described_class.compare('10.0', '10.0')).to eq(0)
    end

    it 'handles different segment counts' do
      expect(described_class.compare('10.0.1', '10.0')).to eq(1)
    end

    it 'handles single vs multi-part versions' do
      expect(described_class.compare('10', '9.5')).to eq(1)
    end
  end

  describe '#initialize' do
    it 'stores original string' do
      version = described_class.new('10.0')
      expect(version.original).to eq('10.0')
    end

    it 'parses segments' do
      version = described_class.new('10.0.5')
      expect(version.segments).to eq([10, 0, 5])
    end

    it 'handles integer input' do
      version = described_class.new(10)
      expect(version.segments).to eq([10])
    end

    it 'handles nil input' do
      version = described_class.new(nil)
      expect(version.segments).to eq([0])
    end
  end

  describe '#<=>' do
    it 'compares 10.0 > 9.5 (the critical bug case)' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('9.5')
      expect(v1 <=> v2).to eq(1)
    end

    it 'compares 9.5 < 10.0' do
      v1 = described_class.new('9.5')
      v2 = described_class.new('10.0')
      expect(v1 <=> v2).to eq(-1)
    end

    it 'compares equal versions as 0' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('10.0')
      expect(v1 <=> v2).to eq(0)
    end

    it 'compares 1.10.0 > 1.9.9' do
      v1 = described_class.new('1.10.0')
      v2 = described_class.new('1.9.9')
      expect(v1 <=> v2).to eq(1)
    end

    it 'compares with string' do
      version = described_class.new('10.0')
      expect(version <=> '9.5').to eq(1)
    end

    it 'compares with integer' do
      version = described_class.new('10.0')
      expect(version <=> 9).to eq(1)
    end

    it 'returns nil for non-comparable' do
      version = described_class.new('10.0')
      expect(version <=> Object.new).to be_nil
    end
  end

  describe '#==' do
    it 'returns true for equal versions' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('10.0')
      expect(v1 == v2).to be true
    end

    it 'returns true for equivalent versions with different segment counts' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('10.0.0')
      expect(v1 == v2).to be true
    end

    it 'returns false for different versions' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('9.5')
      expect(v1 == v2).to be false
    end

    it 'compares with string' do
      version = described_class.new('10.0')
      expect(version == '10.0').to be true
    end
  end

  describe '#>' do
    it 'returns true when greater' do
      expect(described_class.new('10.0')).to be > described_class.new('9.5')
    end

    it 'returns false when equal' do
      expect(described_class.new('10.0')).not_to be > described_class.new('10.0')
    end

    it 'returns false when lesser' do
      expect(described_class.new('9.5')).not_to be > described_class.new('10.0')
    end
  end

  describe '#<' do
    it 'returns true when lesser' do
      expect(described_class.new('9.5')).to be < described_class.new('10.0')
    end

    it 'returns false when equal' do
      expect(described_class.new('10.0')).not_to be < described_class.new('10.0')
    end
  end

  describe '#>=' do
    it 'returns true when greater' do
      expect(described_class.new('10.0')).to be >= described_class.new('9.5')
    end

    it 'returns true when equal' do
      expect(described_class.new('10.0')).to be >= described_class.new('10.0')
    end

    it 'returns false when lesser' do
      expect(described_class.new('9.5')).not_to be >= described_class.new('10.0')
    end
  end

  describe '#<=' do
    it 'returns true when lesser' do
      expect(described_class.new('9.5')).to be <= described_class.new('10.0')
    end

    it 'returns true when equal' do
      expect(described_class.new('10.0')).to be <= described_class.new('10.0')
    end
  end

  describe '#to_s' do
    it 'returns version string' do
      version = described_class.new('10.0.5')
      expect(version.to_s).to eq('10.0.5')
    end
  end

  describe '#inspect' do
    it 'returns inspect string' do
      version = described_class.new('10.0')
      expect(version.inspect).to eq('#<Ukiryu::Models::SemanticVersion 10.0>')
    end
  end

  describe '#hash and #eql?' do
    it 'can be used as hash key' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('10.0')
      v3 = described_class.new('9.5')

      hash = { v1 => 'first', v3 => 'second' }

      expect(hash[v2]).to eq('first')
      expect(hash[v3]).to eq('second')
    end

    it 'eql? returns true for equal versions' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('10.0')
      expect(v1.eql?(v2)).to be true
    end

    it 'eql? returns false for different versions' do
      v1 = described_class.new('10.0')
      v2 = described_class.new('9.5')
      expect(v1.eql?(v2)).to be false
    end
  end

  describe 'Comparable integration' do
    it 'works with Array#max' do
      versions = [
        described_class.new('9.5'),
        described_class.new('10.0'),
        described_class.new('8.0')
      ]
      expect(versions.max.to_s).to eq('10.0')
    end

    it 'works with Array#sort' do
      versions = [
        described_class.new('9.5'),
        described_class.new('10.0'),
        described_class.new('8.0')
      ]
      expect(versions.sort.map(&:to_s)).to eq(['8.0', '9.5', '10.0'])
    end

    it 'works with Array#min' do
      versions = [
        described_class.new('9.5'),
        described_class.new('10.0'),
        described_class.new('8.0')
      ]
      expect(versions.min.to_s).to eq('8.0')
    end
  end

  describe 'real-world Ghostscript case' do
    it 'correctly selects 10.0 over 9.5' do
      v10 = described_class.new('10.0')
      v95 = described_class.new('9.5')

      # This was the bug: alphabetical sort would select 9.5 over 10.0
      # because '9' > '1' in ASCII
      expect([v95, v10].max).to eq(v10)
    end

    it 'demonstrates the bug with string comparison' do
      # Show why string comparison is wrong
      filenames = ['9.5.yaml', '10.0.yaml']

      # WRONG: alphabetical max gives '9.5.yaml' (because '9' > '1')
      alphabetical_max = filenames.max
      expect(alphabetical_max).to eq('9.5.yaml')

      # CORRECT: semantic version comparison gives '10.0.yaml'
      semantic_max = filenames.max_by do |f|
        described_class.new(File.basename(f, '.yaml'))
      end
      expect(semantic_max).to eq('10.0.yaml')
    end
  end
end
