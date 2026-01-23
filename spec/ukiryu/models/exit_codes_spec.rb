# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Models::ExitCodes do
  describe '#meaning' do
    it 'returns meaning for standard exit codes' do
      exit_codes = described_class.new(
        standard: { '0' => 'success', '1' => 'general_error' }
      )

      expect(exit_codes.meaning(0)).to eq('success')
      expect(exit_codes.meaning(1)).to eq('general_error')
    end

    it 'returns meaning for custom exit codes' do
      exit_codes = described_class.new(
        custom: { '3' => 'merge_conflict', '4' => 'permission_denied' }
      )

      expect(exit_codes.meaning(3)).to eq('merge_conflict')
      expect(exit_codes.meaning(4)).to eq('permission_denied')
    end

    it 'prioritizes custom codes over standard codes' do
      exit_codes = described_class.new(
        standard: { '1' => 'general_error' },
        custom: { '1' => 'custom_error' }
      )

      expect(exit_codes.meaning(1)).to eq('custom_error')
    end

    it 'returns nil for undefined codes' do
      exit_codes = described_class.new(
        standard: { '0' => 'success' }
      )

      expect(exit_codes.meaning(99)).to be_nil
    end

    it 'returns nil when no codes are defined' do
      exit_codes = described_class.new

      expect(exit_codes.meaning(0)).to be_nil
    end
  end

  describe '#defined?' do
    it 'returns true for defined codes' do
      exit_codes = described_class.new(
        standard: { '0' => 'success' }
      )

      expect(exit_codes.defined?(0)).to be true
    end

    it 'returns false for undefined codes' do
      exit_codes = described_class.new(
        standard: { '0' => 'success' }
      )

      expect(exit_codes.defined?(99)).to be false
    end
  end

  describe '#success?' do
    it 'returns true for exit code 0' do
      exit_codes = described_class.new

      expect(exit_codes.success?(0)).to be true
    end

    it 'returns false for non-zero exit codes' do
      exit_codes = described_class.new

      expect(exit_codes.success?(1)).to be false
    end

    it 'returns true if code is defined as success' do
      exit_codes = described_class.new(
        standard: { '0' => 'success', '5' => 'success' }
      )

      expect(exit_codes.success?(5)).to be true
    end
  end

  describe '#all_codes' do
    it 'returns merged standard and custom codes' do
      exit_codes = described_class.new(
        standard: { '0' => 'success', '1' => 'general_error' },
        custom: { '3' => 'merge_conflict' }
      )

      all = exit_codes.all_codes

      expect(all['0']).to eq('success')
      expect(all['1']).to eq('general_error')
      expect(all['3']).to eq('merge_conflict')
    end

    it 'returns empty hash when no codes defined' do
      exit_codes = described_class.new

      expect(exit_codes.all_codes).to eq({})
    end
  end

  describe '#standard_codes' do
    it 'returns standard codes' do
      exit_codes = described_class.new(
        standard: { '0' => 'success', '1' => 'general_error' }
      )

      expect(exit_codes.standard_codes).to eq({ '0' => 'success', '1' => 'general_error' })
    end

    it 'returns empty hash when no standard codes' do
      exit_codes = described_class.new

      expect(exit_codes.standard_codes).to eq({})
    end
  end

  describe '#custom_codes' do
    it 'returns custom codes' do
      exit_codes = described_class.new(
        custom: { '3' => 'merge_conflict' }
      )

      expect(exit_codes.custom_codes).to eq({ '3' => 'merge_conflict' })
    end

    it 'returns empty hash when no custom codes' do
      exit_codes = described_class.new

      expect(exit_codes.custom_codes).to eq({})
    end
  end
end
