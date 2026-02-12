# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ukiryu::Tool::Loader do
  describe '.extract_profile_data' do
    # Make private class method accessible
    before { Ukiryu::Tool::Loader.singleton_class.send(:public, :extract_profile_data) }

    context 'with Hash profile' do
      it 'extracts basic profile fields' do
        profile = {
          'name' => 'test_profile',
          'display_name' => 'Test Profile',
          'platforms' => ['windows'],
          'shells' => ['powershell'],
          'option_style' => 'single_dash_equals'
        }

        result = Ukiryu::Tool::Loader.extract_profile_data(profile)

        expect(result[:name]).to eq('test_profile')
        expect(result[:display_name]).to eq('Test Profile')
        expect(result[:platforms]).to eq(['windows'])
        expect(result[:shells]).to eq(['powershell'])
        expect(result[:option_style]).to eq('single_dash_equals')
      end

      it 'extracts inherits field from hash with symbol keys' do
        profile = {
          name: 'windows',
          platforms: ['windows'],
          shells: ['powershell'],
          inherits: 'unix'
        }

        result = Ukiryu::Tool::Loader.extract_profile_data(profile)

        expect(result[:inherits]).to eq('unix')
      end

      it 'extracts inherits field from hash with string keys' do
        profile = {
          'name' => 'windows',
          'platforms' => ['windows'],
          'shells' => ['powershell'],
          'inherits' => 'unix'
        }

        result = Ukiryu::Tool::Loader.extract_profile_data(profile)

        expect(result[:inherits]).to eq('unix')
      end

      it 'extracts executable_name field' do
        profile = {
          'name' => 'windows',
          'executable_name' => 'gswin64c'
        }

        result = Ukiryu::Tool::Loader.extract_profile_data(profile)

        expect(result[:executable_name]).to eq('gswin64c')
      end

      it 'returns nil for missing inherits field' do
        profile = {
          'name' => 'standalone',
          'platforms' => ['windows']
        }

        result = Ukiryu::Tool::Loader.extract_profile_data(profile)

        expect(result[:inherits]).to be_nil
      end
    end

    context 'with object profile' do
      it 'extracts fields from object with accessors' do
        profile_class = Class.new do
          attr_reader :name, :display_name, :platforms, :shells, :option_style, :inherits, :executable_name

          def initialize
            @name = 'object_profile'
            @display_name = 'Object Profile'
            @platforms = ['linux']
            @shells = ['bash']
            @option_style = 'double_dash_equals'
            @inherits = 'base'
            @executable_name = 'custom_exe'
          end
        end

        profile = profile_class.new
        result = Ukiryu::Tool::Loader.extract_profile_data(profile)

        expect(result[:name]).to eq('object_profile')
        expect(result[:display_name]).to eq('Object Profile')
        expect(result[:platforms]).to eq(['linux'])
        expect(result[:shells]).to eq(['bash'])
        expect(result[:option_style]).to eq('double_dash_equals')
        expect(result[:inherits]).to eq('base')
        expect(result[:executable_name]).to eq('custom_exe')
      end

      it 'returns nil for inherits when object does not respond to it' do
        profile_class = Class.new do
          attr_reader :name, :display_name, :platforms, :shells, :option_style

          def initialize
            @name = 'no_inherits'
            @display_name = 'No Inherits'
            @platforms = ['macos']
            @shells = ['zsh']
            @option_style = 'single_dash_space'
          end
        end

        profile = profile_class.new
        result = Ukiryu::Tool::Loader.extract_profile_data(profile)

        expect(result[:inherits]).to be_nil
      end
    end
  end

  describe 'profile inheritance integration' do
    # This tests the full flow: extract_profile_data -> PlatformProfile -> resolve_inheritance!
    it 'preserves inherits field through the conversion process' do
      Ukiryu::Tool::Loader.singleton_class.send(:public, :extract_profile_data)

      # Create a minimal test that verifies the inherits field is preserved
      profile_hash = {
        'name' => 'windows',
        'platforms' => ['windows'],
        'shells' => ['powershell'],
        'inherits' => 'unix'
      }

      extracted = Ukiryu::Tool::Loader.extract_profile_data(profile_hash)

      # The inherits field should be preserved
      expect(extracted[:inherits]).to eq('unix')

      # This would be used by PlatformProfile.resolve_inheritance! to inherit commands
    end
  end
end
