# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Models::Components do
  let(:option_def) do
    Ukiryu::Models::OptionDefinition.new(
      name: 'verbose',
      cli: '--verbose',
      description: 'Verbose output',
      type: 'boolean'
    )
  end

  let(:flag_def) do
    Ukiryu::Models::FlagDefinition.new(
      name: 'help',
      cli: '--help',
      description: 'Show help'
    )
  end

  let(:arg_def) do
    Ukiryu::Models::ArgumentDefinition.new(
      name: 'input',
      type: 'file',
      description: 'Input file'
    )
  end

  describe '#option' do
    it 'returns option by name' do
      components = described_class.new(options: { 'verbose' => option_def })

      expect(components.option('verbose')).to eq(option_def)
    end

    it 'returns nil for undefined option' do
      components = described_class.new

      expect(components.option('verbose')).to be_nil
    end

    it 'handles symbol names' do
      components = described_class.new(options: { 'verbose' => option_def })

      expect(components.option(:verbose)).to eq(option_def)
    end
  end

  describe '#flag' do
    it 'returns flag by name' do
      components = described_class.new(flags: { 'help' => flag_def })

      expect(components.flag('help')).to eq(flag_def)
    end

    it 'returns nil for undefined flag' do
      components = described_class.new

      expect(components.flag('help')).to be_nil
    end
  end

  describe '#argument' do
    it 'returns argument by name' do
      components = described_class.new(arguments: { 'input' => arg_def })

      expect(components.argument('input')).to eq(arg_def)
    end

    it 'returns nil for undefined argument' do
      components = described_class.new

      expect(components.argument('input')).to be_nil
    end
  end

  describe '#can_resolve?' do
    it 'returns true for valid option reference' do
      components = described_class.new(options: { 'verbose' => option_def })

      expect(components.can_resolve?('#/components/options/verbose')).to be true
    end

    it 'returns true for valid flag reference' do
      components = described_class.new(flags: { 'help' => flag_def })

      expect(components.can_resolve?('#/components/flags/help')).to be true
    end

    it 'returns true for valid argument reference' do
      components = described_class.new(arguments: { 'input' => arg_def })

      expect(components.can_resolve?('#/components/arguments/input')).to be true
    end

    it 'returns false for undefined reference' do
      components = described_class.new

      expect(components.can_resolve?('#/components/options/verbose')).to be false
    end

    it 'returns false for invalid reference format' do
      components = described_class.new

      expect(components.can_resolve?('invalid-ref')).to be false
    end
  end

  describe '#resolve' do
    it 'resolves option reference' do
      components = described_class.new(options: { 'verbose' => option_def })

      result = components.resolve('#/components/options/verbose')

      expect(result).to eq(option_def)
    end

    it 'resolves flag reference' do
      components = described_class.new(flags: { 'help' => flag_def })

      result = components.resolve('#/components/flags/help')

      expect(result).to eq(flag_def)
    end

    it 'resolves argument reference' do
      components = described_class.new(arguments: { 'input' => arg_def })

      result = components.resolve('#/components/arguments/input')

      expect(result).to eq(arg_def)
    end

    it 'returns nil for undefined reference' do
      components = described_class.new

      result = components.resolve('#/components/options/verbose')

      expect(result).to be_nil
    end

    it 'returns nil for invalid reference format' do
      components = described_class.new

      result = components.resolve('invalid-ref')

      expect(result).to be_nil
    end
  end
end
