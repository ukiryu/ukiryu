# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Extractors::HelpParser do
  let(:options) { {} }

  describe '#available?' do
    context 'with a tool that does not exist' do
      it 'returns false' do
        parser = described_class.new('nonexistent_tool_xyz', options)
        expect(parser.available?).to be false
      end
    end

    context 'with a tool that has help output' do
      it 'returns true' do
        parser = described_class.new('git', options)
        expect(parser.available?).to be true
      end
    end
  end

  describe '#extract' do
    context 'with a tool that has help output' do
      it 'returns YAML definition' do
        parser = described_class.new('git', options)
        yaml = parser.extract

        expect(yaml).not_to be_nil
        expect(yaml).to include('git')
        expect(yaml).to include('ukiryu_schema')
      end

      it 'includes required fields' do
        parser = described_class.new('git', options)
        yaml = parser.extract

        expect(yaml).to include('name:')
        expect(yaml).to include('version:')
        expect(yaml).to include('profiles:')
      end
    end
  end
end
