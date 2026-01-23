# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Models::CommandDefinition do
  let(:command) { described_class.new }

  describe '#initialize' do
    it 'creates a command with default values' do
      cmd = described_class.new(name: 'test')
      expect(cmd.name).to eq('test')
      expect(cmd.options).to be_nil
      expect(cmd.flags).to be_nil
      expect(cmd.arguments).to be_nil
    end

    it 'creates a command with exit codes' do
      exit_codes = Ukiryu::Models::ExitCodes.new(
        standard: { 0 => 'success', 1 => 'error' },
        custom: { 2 => 'invalid_input' }
      )
      cmd = described_class.new(
        name: 'convert',
        exit_codes: exit_codes
      )
      expect(cmd.name).to eq('convert')
      expect(cmd.exit_codes).to eq(exit_codes)
      expect(cmd.exit_codes.standard_codes).to eq({ 0 => 'success', 1 => 'error' })
      expect(cmd.exit_codes.custom_codes).to eq({ 2 => 'invalid_input' })
    end
  end

  describe '#exit_codes' do
    it 'can have exit codes with standard codes only' do
      exit_codes = Ukiryu::Models::ExitCodes.new(
        standard: { 0 => 'success', 1 => 'general_error' }
      )
      cmd = described_class.new(
        name: 'test',
        exit_codes: exit_codes
      )
      expect(cmd.exit_codes.standard_codes).to eq({ 0 => 'success', 1 => 'general_error' })
      expect(cmd.exit_codes.custom_codes).to eq({})
    end

    it 'can have exit codes with custom codes only' do
      exit_codes = Ukiryu::Models::ExitCodes.new(
        custom: { 3 => 'merge_conflict', 4 => 'network_error' }
      )
      cmd = described_class.new(
        name: 'merge',
        exit_codes: exit_codes
      )
      expect(cmd.exit_codes.custom_codes).to eq({ 3 => 'merge_conflict', 4 => 'network_error' })
      expect(cmd.exit_codes.standard_codes).to eq({})
    end

    it 'returns nil when no exit codes defined' do
      cmd = described_class.new(name: 'test')
      expect(cmd.exit_codes).to be_nil
    end
  end

  describe '#belongs_to_command?' do
    it 'returns true when belongs_to is set' do
      cmd = described_class.new(
        name: 'add',
        belongs_to: 'remote'
      )
      expect(cmd.belongs_to_command?).to be true
    end

    it 'returns false when belongs_to is not set' do
      cmd = described_class.new(name: 'add')
      expect(cmd.belongs_to_command?).to be false
    end
  end

  describe '#flag_action?' do
    it 'returns true when cli_flag is set' do
      cmd = described_class.new(
        name: 'delete',
        cli_flag: '-d'
      )
      expect(cmd.flag_action?).to be true
    end

    it 'returns false when cli_flag is not set' do
      cmd = described_class.new(name: 'delete')
      expect(cmd.flag_action?).to be false
    end
  end

  describe '#option' do
    let(:options) do
      [
        Ukiryu::Models::OptionDefinition.new(name: 'output', cli: '-o'),
        Ukiryu::Models::OptionDefinition.new(name: 'verbose', cli: '-v')
      ]
    end

    it 'returns an option by name' do
      cmd = described_class.new(name: 'test', options: options)
      expect(cmd.option('output').name).to eq('output')
    end

    it 'returns nil for unknown option' do
      cmd = described_class.new(name: 'test', options: options)
      expect(cmd.option('unknown')).to be_nil
    end
  end

  describe '#flag' do
    let(:flags) do
      [
        Ukiryu::Models::FlagDefinition.new(name: 'verbose', cli: '-v'),
        Ukiryu::Models::FlagDefinition.new(name: 'quiet', cli: '-q')
      ]
    end

    it 'returns a flag by name' do
      cmd = described_class.new(name: 'test', flags: flags)
      expect(cmd.flag('verbose').name).to eq('verbose')
    end

    it 'returns nil for unknown flag' do
      cmd = described_class.new(name: 'test', flags: flags)
      expect(cmd.flag('unknown')).to be_nil
    end
  end

  describe '#argument' do
    let(:arguments) do
      [
        Ukiryu::Models::ArgumentDefinition.new(name: 'input', type: 'file'),
        Ukiryu::Models::ArgumentDefinition.new(name: 'output', type: 'file')
      ]
    end

    it 'returns an argument by name' do
      cmd = described_class.new(name: 'test', arguments: arguments)
      expect(cmd.argument('input').name).to eq('input')
    end

    it 'returns nil for unknown argument' do
      cmd = described_class.new(name: 'test', arguments: arguments)
      expect(cmd.argument('unknown')).to be_nil
    end
  end

  describe 'YAML serialization' do
    it 'serializes command with exit codes to YAML' do
      exit_codes = Ukiryu::Models::ExitCodes.new(
        standard: { 0 => 'success', 1 => 'error' },
        custom: { 3 => 'merge_conflict' }
      )
      cmd = described_class.new(
        name: 'merge',
        description: 'Merge branches',
        exit_codes: exit_codes
      )

      yaml = cmd.to_yaml
      expect(yaml).to include('name: merge')
      expect(yaml).to include('description: Merge branches')
      expect(yaml).to include('exit_codes:')
      expect(yaml).to include('standard:')
      expect(yaml).to include('custom:')
    end

    it 'deserializes command with exit codes from YAML' do
      yaml = <<~YAML
        name: merge
        description: Merge branches
        exit_codes:
          standard:
            0: success
            1: error
          custom:
            3: merge_conflict
      YAML

      cmd = described_class.from_yaml(yaml)
      expect(cmd.name).to eq('merge')
      expect(cmd.description).to eq('Merge branches')
      expect(cmd.exit_codes).not_to be_nil
      expect(cmd.exit_codes.standard_codes).to eq({ 0 => 'success', 1 => 'error' })
      expect(cmd.exit_codes.custom_codes).to eq({ 3 => 'merge_conflict' })
    end
  end
end
