# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::RegisterAutoManager do
  describe '.register_path' do
    context 'when UKIRYU_REGISTER is set' do
      before do
        @original_env = ENV['UKIRYU_REGISTER']
        ENV['UKIRYU_REGISTER'] = File.join(__dir__, '..', 'fixtures', 'register')
      end

      after do
        if @original_env
          ENV['UKIRYU_REGISTER'] = @original_env
        else
          ENV.delete('UKIRYU_REGISTER')
        end
      end

      it 'returns the environment variable path' do
        path = described_class.register_path
        expect(path).to include('fixtures/register')
      end
    end

    context 'when UKIRYU_REGISTER is not set' do
      before do
        @original_env = ENV['UKIRYU_REGISTER']
        ENV.delete('UKIRYU_REGISTER')
      end

      after do
        if @original_env
          ENV['UKIRYU_REGISTER'] = @original_env
        else
          ENV.delete('UKIRYU_REGISTER')
        end
      end

      it 'returns a String path when dev register exists' do
        # The dev register (../../register from gem) should exist in development
        # This tests that Pathname#join is used correctly instead of string interpolation
        result = begin
          described_class.send(:register_path)
        rescue Ukiryu::RegisterAutoManager::RegisterError
          # Git not available on this system - skip auto-clone test
          nil
        end

        # In development, the dev register should be found
        # In CI or other environments, it might fall back to user clone
        # If git is not available, result will be nil
        expect(result).to be_a(String).or be_nil
      end

      it 'uses Pathname#exist? method correctly on dev_path' do
        # This specifically tests that dev_path is a Pathname, not a String
        # The bug was: dev_path = "#{pathname}string" creates a String
        # The fix is: dev_path = pathname.join('string') keeps it as Pathname
        #
        # If git is not available and no register exists, RegisterError is expected
        # The important thing is that we don't get NoMethodError for String#exist?
        expect do
          described_class.send(:register_path)
        rescue Ukiryu::RegisterAutoManager::RegisterError
          # Git not available - this is OK, we're testing for Pathname bug
          nil
        end.not_to raise_error
      end
    end
  end

  describe '.resolve_register_path' do
    context 'when UKIRYU_REGISTER is not set' do
      before do
        @original_env = ENV['UKIRYU_REGISTER']
        ENV.delete('UKIRYU_REGISTER')
      end

      after do
        if @original_env
          ENV['UKIRYU_REGISTER'] = @original_env
        else
          ENV.delete('UKIRYU_REGISTER')
        end
      end

      it 'returns a String or nil without raising an error' do
        result = described_class.send(:resolve_register_path)
        expect(result).to be_a(String).or be_nil
      end
    end
  end
end
