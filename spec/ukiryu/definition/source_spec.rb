# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::Source do
  # Create a concrete test class for the abstract Source class
  class TestSource < Ukiryu::Definition::Source
    attr_reader :content, :test_cache_key

    def initialize(content, test_cache_key)
      @content = content
      @test_cache_key = test_cache_key
    end

    def load
      @content
    end

    def cache_key
      @test_cache_key
    end

    def source_type
      :test
    end
  end

  describe 'abstract interface' do
    it 'raises NotImplementedError for unimplemented #load' do
      source = described_class.new
      expect { source.load }.to raise_error(NotImplementedError, /must implement #load/)
    end

    it 'raises NotImplementedError for unimplemented #cache_key' do
      source = described_class.new
      expect { source.cache_key }.to raise_error(NotImplementedError, /must implement #cache_key/)
    end

    it 'raises NotImplementedError for unimplemented #source_type' do
      source = described_class.new
      expect { source.source_type }.to raise_error(NotImplementedError, /must implement #source_type/)
    end
  end

  describe 'equality' do
    it 'considers sources with same cache key as equal' do
      source1 = TestSource.new('content1', 'test:key1')
      source2 = TestSource.new('content2', 'test:key1')

      expect(source1).to eq(source2)
    end

    it 'considers sources with different cache keys as not equal' do
      source1 = TestSource.new('content', 'test:key1')
      source2 = TestSource.new('content', 'test:key2')

      expect(source1).not_to eq(source2)
    end

    it 'is not equal to non-source objects' do
      source = TestSource.new('content', 'test:key1')

      expect(source).not_to eq('test:key1')
      expect(source).not_to eq(nil)
    end
  end

  describe 'hash' do
    it 'generates hash code based on cache key' do
      source1 = TestSource.new('content1', 'test:key1')
      source2 = TestSource.new('content2', 'test:key1')
      source3 = TestSource.new('content3', 'test:key2')

      expect(source1.hash).to eq(source2.hash)
      expect(source1.hash).not_to eq(source3.hash)
    end

    it 'can be used as hash key' do
      source1 = TestSource.new('content1', 'test:key1')
      source2 = TestSource.new('content2', 'test:key1')
      source3 = TestSource.new('content3', 'test:key2')

      hash = {}
      hash[source1] = 'value1'
      hash[source3] = 'value3'

      expect(hash[source1]).to eq('value1')
      expect(hash[source2]).to eq('value1') # Same cache key
      expect(hash[source3]).to eq('value3')
    end
  end

  describe '#to_s' do
    it 'returns string representation with source type and cache key' do
      source = TestSource.new('content', 'test:key123')

      expect(source.to_s).to eq('test:test:key123')
    end
  end

  describe '#inspect' do
    it 'returns detailed inspection string' do
      source = TestSource.new('content', 'test:key123')

      expect(source.inspect).to eq('#<TestSource source_type=test cache_key=test:key123>')
    end
  end

  describe '#sha256 (protected method)' do
    it 'calculates SHA256 hash of a string' do
      source = TestSource.new('test', 'key')

      # SHA256 of 'test' is known value
      expected_hash = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08'

      expect(source.send(:sha256, 'test')).to eq(expected_hash)
    end

    it 'produces consistent hashes for same input' do
      source = TestSource.new('test', 'key')

      hash1 = source.send(:sha256, 'consistent')
      hash2 = source.send(:sha256, 'consistent')

      expect(hash1).to eq(hash2)
    end

    it 'produces different hashes for different inputs' do
      source = TestSource.new('test', 'key')

      hash1 = source.send(:sha256, 'input1')
      hash2 = source.send(:sha256, 'input2')

      expect(hash1).not_to eq(hash2)
    end
  end
end
