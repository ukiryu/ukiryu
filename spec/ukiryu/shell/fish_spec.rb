# frozen_string_literal: true

require 'spec_helper'
require_relative 'unix_base_shared_examples'

RSpec.describe Ukiryu::Shell::Fish do
  let(:shell) { described_class.new }

  describe '#name' do
    it 'returns :fish' do
      expect(shell.name).to eq(:fish)
    end
  end

  describe '#shell_command' do
    it 'returns "fish"' do
      expect(shell.shell_command).to eq('fish')
    end
  end

  # Include shared Unix shell behaviors
  it_behaves_like 'a Unix shell' do
    let(:subject) { shell }
  end

  it_behaves_like 'a Unix shell with headless support' do
    let(:subject) { shell }
  end
end
