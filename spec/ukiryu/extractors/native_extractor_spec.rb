# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Extractors::NativeExtractor do
  let(:options) { {} }

  describe '#available?' do
    context 'with a tool that does not exist' do
      it 'returns false' do
        extractor = described_class.new('nonexistent_tool_xyz', options)
        expect(extractor.available?).to be false
      end
    end

    context 'with a tool that exists but does not support native flag' do
      it 'returns false if tool does not mention ukiryu in help' do
        # Use git as it's commonly available but doesn't support --ukiryu-definition
        extractor = described_class.new('git', options)
        expect(extractor.available?).to be false
      end
    end
  end

  describe '#extract' do
    context 'with a tool that does not support native flag' do
      it 'returns nil' do
        extractor = described_class.new('git', options)
        result = extractor.extract
        # git doesn't support --ukiryu-definition
        expect(result).to be_nil
      end
    end
  end
end
