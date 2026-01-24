# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::ValidationResult do
  describe '.success' do
    it 'creates a valid result' do
      result = described_class.success
      expect(result).to be_valid
      expect(result).not_to be_invalid
    end
  end

  describe '.failure' do
    it 'creates an invalid result with errors' do
      result = described_class.failure(['Error 1', 'Error 2'])
      expect(result).to be_invalid
      expect(result).not_to be_valid
      expect(result.error_count).to eq(2)
    end

    it 'accepts warnings' do
      result = described_class.failure(['Error'], ['Warning'])
      expect(result.error_count).to eq(1)
      expect(result.warning_count).to eq(1)
    end
  end

  describe '.with_warnings' do
    it 'creates a valid result with warnings' do
      result = described_class.with_warnings(['Warning 1', 'Warning 2'])
      expect(result).to be_valid
      expect(result.warning_count).to eq(2)
    end
  end

  describe '#valid?' do
    it 'returns true for valid results' do
      result = described_class.new(valid: true)
      expect(result).to be_valid
    end

    it 'returns false for invalid results' do
      result = described_class.new(valid: false)
      expect(result).not_to be_valid
    end
  end

  describe '#invalid?' do
    it 'returns true for invalid results' do
      result = described_class.new(valid: false)
      expect(result).to be_invalid
    end

    it 'returns false for valid results' do
      result = described_class.new(valid: true)
      expect(result).not_to be_invalid
    end
  end

  describe '#has_errors?' do
    it 'returns true when there are errors' do
      result = described_class.new(valid: false, errors: ['Error'])
      expect(result).to have_errors
    end

    it 'returns false when there are no errors' do
      result = described_class.new(valid: true, errors: [])
      expect(result).not_to have_errors
    end
  end

  describe '#has_warnings?' do
    it 'returns true when there are warnings' do
      result = described_class.new(valid: true, warnings: ['Warning'])
      expect(result).to have_warnings
    end

    it 'returns false when there are no warnings' do
      result = described_class.new(valid: true, warnings: [])
      expect(result).not_to have_warnings
    end
  end

  describe '#issue_count' do
    it 'returns total number of issues' do
      result = described_class.new(
        valid: false,
        errors: %w[e1 e2],
        warnings: %w[w1 w2 w3]
      )
      expect(result.issue_count).to eq(5)
    end
  end

  describe '#summary' do
    it 'returns "Valid" for clean validation' do
      result = described_class.new(valid: true)
      expect(result.summary).to eq('Valid')
    end

    it 'returns "Valid with N warning(s)" for warnings' do
      result = described_class.new(valid: true, warnings: %w[a b])
      expect(result.summary).to eq('Valid with 2 warning(s)')
    end

    it 'returns "Invalid (N error(s)" for errors' do
      result = described_class.new(valid: false, errors: %w[a b c])
      expect(result.summary).to eq('Invalid (3 error(s))')
    end

    it 'includes both errors and warnings in summary' do
      result = described_class.new(
        valid: false,
        errors: ['a'],
        warnings: %w[b c]
      )
      expect(result.summary).to eq('Invalid (1 error(s), 2 warning(s))')
    end
  end

  describe '#to_s' do
    it 'formats errors correctly' do
      result = described_class.new(
        valid: false,
        errors: ['First error', 'Second error']
      )
      output = result.to_s
      expect(output).to include('Validation: Invalid')
      expect(output).to include('Errors:')
      expect(output).to include('1. First error')
      expect(output).to include('2. Second error')
    end

    it 'formats warnings correctly' do
      result = described_class.new(
        valid: true,
        warnings: ['First warning']
      )
      output = result.to_s
      expect(output).to include('Validation: Valid with 1 warning(s)')
      expect(output).to include('Warnings:')
      expect(output).to include('1. First warning')
    end
  end

  describe '#to_h' do
    it 'converts result to hash' do
      result = described_class.new(
        valid: false,
        errors: ['e1'],
        warnings: ['w1']
      )
      hash = result.to_h
      expect(hash[:valid]).to be false
      expect(hash[:errors]).to eq(['e1'])
      expect(hash[:warnings]).to eq(['w1'])
      expect(hash[:error_count]).to eq(1)
      expect(hash[:warning_count]).to eq(1)
    end
  end

  describe '#to_json' do
    it 'converts result to JSON' do
      result = described_class.new(
        valid: true,
        warnings: ['w1']
      )
      json = result.to_json
      parsed = JSON.parse(json)
      expect(parsed['valid']).to be true
      expect(parsed['warnings']).to eq(['w1'])
    end
  end
end
