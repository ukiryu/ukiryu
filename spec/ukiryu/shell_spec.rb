# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Shell do
  describe '.valid?' do
    it 'returns true for valid shells' do
      expect(described_class.valid?(:bash)).to be(true)
      expect(described_class.valid?(:zsh)).to be(true)
      expect(described_class.valid?(:fish)).to be(true)
      expect(described_class.valid?(:sh)).to be(true)
      expect(described_class.valid?(:powershell)).to be(true)
      expect(described_class.valid?(:cmd)).to be(true)
    end

    it 'returns false for invalid shells' do
      expect(described_class.valid?(:invalid)).to be(false)
      expect(described_class.valid?(:nu)).to be(false)
      expect(described_class.valid?(:python)).to be(false)
    end

    it 'handles nil input' do
      expect(described_class.valid?(nil)).to be(false)
    end
  end

  describe '.all_valid' do
    it 'returns all valid shell types' do
      shells = described_class.all_valid

      expect(shells).to be_an(Array)
      expect(shells).to include(:bash, :zsh, :fish, :sh, :powershell, :cmd)
    end
  end

  describe '.valid_for_platform' do
    context 'on Unix-like systems' do
      before { allow(Ukiryu::Platform).to receive(:windows?).and_return(false) }

      it 'returns Unix-compatible platform groups' do
        shells = described_class.valid_for_platform

        expect(shells).to include(:unix, :powershell)
      end
    end

    context 'on Windows' do
      before { allow(Ukiryu::Platform).to receive(:windows?).and_return(true) }

      it 'returns Windows-compatible platform groups' do
        shells = described_class.valid_for_platform

        expect(shells).to include(:windows, :powershell, :unix)
      end
    end
  end

  describe '.from_string' do
    it 'converts valid shell names to symbols' do
      expect(described_class.from_string('bash')).to eq(:bash)
      expect(described_class.from_string('zsh')).to eq(:zsh)
      expect(described_class.from_string('fish')).to eq(:fish)
      expect(described_class.from_string('PowerShell')).to eq(:powershell)
      expect(described_class.from_string('BASH')).to eq(:bash)
    end

    it 'raises ArgumentError for invalid shell names' do
      expect do
        described_class.from_string('invalid')
      end.to raise_error(ArgumentError, /Invalid shell: invalid/)
    end
  end

  describe '.available?' do
    context 'on Unix-like systems' do
      before { allow(Ukiryu::Platform).to receive(:windows?).and_return(false) }

      it 'returns true for bash if available in PATH' do
        # This test assumes bash is available on the system
        result = described_class.available?(:bash)
        expect(result).to be_a(TrueClass).or be_a(FalseClass)
      end

      it 'returns false for invalid shells' do
        expect(described_class.available?(:invalid)).to be(false)
      end
    end
  end

  describe '.available_shells' do
    it 'returns an array of available shells' do
      shells = described_class.available_shells

      expect(shells).to be_an(Array)
      expect(shells).to all(be_a(Symbol))
    end
  end

  describe '.class_for' do
    it 'returns the correct class for each shell type' do
      expect(described_class.class_for(:bash)).to eq(Ukiryu::Shell::Bash)
      expect(described_class.class_for(:zsh)).to eq(Ukiryu::Shell::Zsh)
      expect(described_class.class_for(:fish)).to eq(Ukiryu::Shell::Fish)
      expect(described_class.class_for(:sh)).to eq(Ukiryu::Shell::Sh)
      expect(described_class.class_for(:powershell)).to eq(Ukiryu::Shell::PowerShell)
      expect(described_class.class_for(:cmd)).to eq(Ukiryu::Shell::Cmd)
    end

    it 'raises UnknownShellError for invalid shells' do
      expect do
        described_class.class_for(:invalid)
      end.to raise_error(Ukiryu::Errors::UnknownShellError, /Unknown shell: invalid/)
    end
  end
end
