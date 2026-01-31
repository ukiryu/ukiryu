# frozen_string_literal: true

require 'spec_helper'
require_relative 'unix_base_shared_examples'

RSpec.describe Ukiryu::Shell::Zsh do
  let(:shell) { described_class.new }

  describe '#name' do
    it 'returns :zsh' do
      expect(shell.name).to eq(:zsh)
    end
  end

  describe '#shell_command' do
    it 'returns "zsh"' do
      expect(shell.shell_command).to eq('zsh')
    end
  end

  # Include shared Unix shell behaviors
  it_behaves_like 'a Unix shell' do
    let(:subject) { shell }
  end

  it_behaves_like 'a Unix shell with headless support' do
    let(:subject) { shell }
  end

  # Zsh-specific tests
  describe 'unique Zsh behaviors' do
    it 'has proper shell detection' do
      expect(shell.name).to eq(:zsh)
      expect(shell.shell_command).to eq('zsh')
    end
  end
end
