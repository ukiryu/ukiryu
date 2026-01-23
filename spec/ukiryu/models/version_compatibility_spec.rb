# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::VersionCompatibility do
  describe '.check' do
    context 'with no requirement' do
      it 'returns compatible result' do
        result = described_class.check('2.45.0', nil)

        expect(result.compatible?).to be true
        expect(result.installed_version).to eq('2.45.0')
      end

      it 'returns compatible result for empty string' do
        result = described_class.check('2.45.0', '')

        expect(result.compatible?).to be true
        expect(result.installed_version).to eq('2.45.0')
      end
    end

    context 'with equality requirement' do
      it 'returns compatible for exact match' do
        result = described_class.check('2.45.0', '== 2.45.0')

        expect(result.compatible?).to be true
      end

      it 'returns compatible for simple equality' do
        result = described_class.check('2.45.0', '2.45.0')

        expect(result.compatible?).to be true
      end

      it 'returns incompatible for different version' do
        result = described_class.check('2.45.0', '2.46.0')

        expect(result.compatible?).to be false
        expect(result.reason).to include('does not satisfy')
      end
    end

    context 'with greater than requirement' do
      it 'returns compatible for higher version' do
        result = described_class.check('2.45.0', '> 2.30')

        expect(result.compatible?).to be true
      end

      it 'returns compatible for equal version with >=' do
        result = described_class.check('2.45.0', '>= 2.45.0')

        expect(result.compatible?).to be true
      end

      it 'returns incompatible for lower version' do
        result = described_class.check('2.29.0', '>= 2.30')

        expect(result.compatible?).to be false
      end
    end

    context 'with less than requirement' do
      it 'returns compatible for lower version' do
        result = described_class.check('2.29.0', '< 2.30')

        expect(result.compatible?).to be true
      end

      it 'returns compatible for equal version with <=' do
        result = described_class.check('2.30.0', '<= 2.30.0')

        expect(result.compatible?).to be true
      end

      it 'returns incompatible for higher version' do
        result = described_class.check('2.31.0', '< 2.30')

        expect(result.compatible?).to be false
      end
    end

    context 'with optimistic operator (~>)' do
      it 'returns compatible for version within range' do
        result = described_class.check('2.5.1', '~> 2.5')

        expect(result.compatible?).to be true
      end

      it 'returns compatible for minimum version' do
        result = described_class.check('2.5.0', '~> 2.5')

        expect(result.compatible?).to be true
      end

      it 'returns incompatible for next major version' do
        result = described_class.check('3.0.0', '~> 2.5')

        expect(result.compatible?).to be false
      end
    end

    context 'with multiple requirements' do
      it 'returns compatible when all satisfied' do
        result = described_class.check('2.45.0', '>= 2.30, < 3.0')

        expect(result.compatible?).to be true
      end

      it 'returns incompatible when one fails' do
        result = described_class.check('3.0.0', '>= 2.30, < 3.0')

        expect(result.compatible?).to be false
      end
    end

    context 'with not equal requirement' do
      it 'returns compatible for different version' do
        result = described_class.check('2.45.0', '!= 2.46.0')

        expect(result.compatible?).to be true
      end

      it 'returns incompatible for equal version' do
        result = described_class.check('2.45.0', '!= 2.45.0')

        expect(result.compatible?).to be false
      end
    end
  end

  describe '#status_message' do
    it 'returns compatibility message for compatible versions' do
      result = described_class.new(
        installed_version: '2.45.0',
        required_version: '>= 2.30',
        compatible: true
      )

      expect(result.status_message).to include('is compatible')
    end

    it 'returns reason for incompatible versions' do
      result = described_class.new(
        installed_version: '2.29.0',
        required_version: '>= 2.30',
        compatible: false,
        reason: 'Version 2.29.0 is too old'
      )

      expect(result.status_message).to eq('Version 2.29.0 is too old')
    end
  end

  describe '#incompatible?' do
    it 'returns true when not compatible' do
      result = described_class.new(
        installed_version: '2.29.0',
        required_version: '>= 2.30',
        compatible: false
      )

      expect(result.incompatible?).to be true
    end

    it 'returns false when compatible' do
      result = described_class.new(
        installed_version: '2.45.0',
        required_version: '>= 2.30',
        compatible: true
      )

      expect(result.incompatible?).to be false
    end
  end
end
