# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Extractors::Extractor do
  describe '.extract' do
    context 'with method: :native' do
      it 'attempts native extraction' do
        result = described_class.extract('git', method: :native)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:success)
        expect(result).to have_key(:method)
        expect(result).to have_key(:yaml)
        expect(result).to have_key(:error)
      end

      it 'returns method as :native' do
        result = described_class.extract('git', method: :native)
        expect(result[:method]).to eq(:native)
      end
    end

    context 'with method: :help' do
      it 'attempts help parsing' do
        result = described_class.extract('git', method: :help)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:success)
        expect(result[:method]).to eq(:help)
      end
    end

    context 'with method: :auto (default)' do
      it 'tries native first, then help' do
        result = described_class.extract('git', method: :auto)

        expect(result).to be_a(Hash)
        # git doesn't support native, so it should fall back to help
        expect(result[:method]).to eq(:help)
      end
    end

    context 'with nonexistent tool' do
      it 'returns failure result' do
        result = described_class.extract('nonexistent_tool_xyz')

        expect(result[:success]).to be false
        expect(result[:error]).not_to be_nil
      end
    end

    context 'with invalid method' do
      it 'returns error result' do
        result = described_class.extract('git', method: :invalid)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Unknown extraction method')
      end
    end
  end
end
