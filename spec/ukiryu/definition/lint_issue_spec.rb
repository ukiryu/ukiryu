# frozen_string_literal: true

require 'ukiryu'

RSpec.describe Ukiryu::Definition::LintIssue do
  describe '.error' do
    it 'creates an error issue' do
      issue = described_class.error('Test error')
      expect(issue).to be_an_error
      expect(issue).not_to be_a_warning
      expect(issue.message).to eq('Test error')
      expect(issue.severity_string).to eq('ERROR')
    end

    it 'accepts location and suggestion' do
      issue = described_class.error('Test error', location: 'line 5', suggestion: 'Fix it')
      expect(issue.has_location?).to be true
      expect(issue.has_suggestion?).to be true
      expect(issue.location).to eq('line 5')
      expect(issue.suggestion).to eq('Fix it')
    end
  end

  describe '.warning' do
    it 'creates a warning issue' do
      issue = described_class.warning('Test warning')
      expect(issue).to be_a_warning
      expect(issue).not_to be_an_error
      expect(issue.severity_string).to eq('WARNING')
    end
  end

  describe '.info' do
    it 'creates an info issue' do
      issue = described_class.info('Test info')
      expect(issue).to be_info
      expect(issue.severity_string).to eq('INFO')
    end
  end

  describe '.style' do
    it 'creates a style issue' do
      issue = described_class.style('Test style')
      expect(issue).to be_style
      expect(issue.severity_string).to eq('STYLE')
    end
  end

  describe '#has_suggestion?' do
    it 'returns true when suggestion is present' do
      issue = described_class.error('Test', suggestion: 'Fix it')
      expect(issue.has_suggestion?).to be true
    end

    it 'returns false when suggestion is nil' do
      issue = described_class.error('Test')
      expect(issue.has_suggestion?).to be false
    end

    it 'returns false when suggestion is empty' do
      issue = described_class.error('Test', suggestion: '')
      expect(issue.has_suggestion?).to be false
    end
  end

  describe '#has_location?' do
    it 'returns true when location is present' do
      issue = described_class.error('Test', location: 'line 5')
      expect(issue.has_location?).to be true
    end

    it 'returns false when location is nil' do
      issue = described_class.error('Test')
      expect(issue.has_location?).to be false
    end
  end

  describe '#to_s' do
    it 'formats issue without location or suggestion' do
      issue = described_class.error('Test error')
      expect(issue.to_s).to eq('[ERROR] Test error')
    end

    it 'formats issue with location' do
      issue = described_class.error('Test error', location: 'line 5')
      expect(issue.to_s).to eq('[ERROR] Test error (at line 5)')
    end

    it 'formats issue with suggestion' do
      issue = described_class.error('Test error', suggestion: 'Fix it')
      expect(issue.to_s).to eq("[ERROR] Test error\n  Suggestion: Fix it")
    end

    it 'formats issue with both location and suggestion' do
      issue = described_class.error('Test error', location: 'line 5', suggestion: 'Fix it')
      output = issue.to_s
      expect(output).to include('[ERROR] Test error (at line 5)')
      expect(output).to include('Suggestion: Fix it')
    end
  end

  describe '#to_h' do
    it 'converts issue to hash' do
      issue = described_class.error(
        'Test error',
        location: 'line 5',
        suggestion: 'Fix it',
        rule_id: 'test_rule'
      )
      hash = issue.to_h
      expect(hash[:severity]).to eq(:error)
      expect(hash[:severity_string]).to eq('ERROR')
      expect(hash[:message]).to eq('Test error')
      expect(hash[:location]).to eq('line 5')
      expect(hash[:suggestion]).to eq('Fix it')
      expect(hash[:rule_id]).to eq('test_rule')
    end
  end
end
