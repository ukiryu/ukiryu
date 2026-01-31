# frozen_string_literal: true

require 'spec_helper'
require 'ukiryu/version_scheme_resolver'

RSpec.describe Ukiryu::VersionSchemeResolver do
  describe '.resolve' do
    context 'with symbol reference' do
      it 'loads Versionian built-in semantic scheme' do
        scheme = described_class.resolve(:semantic)

        expect(scheme).to be_a(Versionian::VersionScheme)
        expect(scheme.name).to eq(:semantic)
      end

      it 'loads Versionian calver scheme' do
        scheme = described_class.resolve(:calver)

        expect(scheme).to be_a(Versionian::VersionScheme)
        expect(scheme.name).to eq(:calver)
      end
    end

    context 'with inline declaration' do
      it 'creates declarative scheme from hash' do
        declaration = {
          'name' => 'date_with_stage',
          'type' => 'declarative',
          'description' => 'Date (YYYYMMDD) with optional prerelease stage',
          'components' => [
            { 'name' => 'date', 'type' => 'integer', 'separator' => '' },
            {
              'name' => 'stage',
              'type' => 'prerelease',
              'prefix' => '-',
              'optional' => true
            }
          ]
        }

        scheme = described_class.resolve(declaration)

        expect(scheme).to be_a(Versionian::VersionScheme)
        expect(scheme.name).to eq(:date_with_stage)
      end

      it 'supports version comparison for date-with-stage versions' do
        declaration = {
          'name' => 'date_with_stage',
          'type' => 'declarative',
          'description' => 'Date (YYYYMMDD) with optional prerelease stage',
          'components' => [
            { 'name' => 'date', 'type' => 'integer', 'separator' => '' },
            {
              'name' => 'stage',
              'type' => 'prerelease',
              'prefix' => '-',
              'optional' => true
            }
          ]
        }

        scheme = described_class.resolve(declaration)

        # Parse and compare date-with-stage versions (with dot separator)
        expect(scheme.compare('20020101-alpha.3', '20020101-beta.1')).to eq(-1)
        expect(scheme.compare('20020101-beta.1', '20020101-rc.1')).to eq(-1)

        # Date takes priority over stage
        expect(scheme.compare('20020102-alpha.1', '20020101-rc.1')).to eq(1)
      end

      it 'creates build number scheme' do
        declaration = {
          'name' => 'build_number',
          'type' => 'declarative',
          'description' => 'Build number with optional suffix',
          'components' => [
            { 'name' => 'build', 'type' => 'integer', 'prefix' => 'build_' },
            {
              'name' => 'suffix',
              'type' => 'string',
              'prefix' => '_',
              'optional' => true
            }
          ]
        }

        scheme = described_class.resolve(declaration)

        expect(scheme).to be_a(Versionian::VersionScheme)
        expect(scheme.name).to eq(:build_number)
      end
    end

    context 'with invalid input' do
      it 'raises ArgumentError for invalid specification' do
        expect do
          described_class.resolve(123)
        end.to raise_error(ArgumentError, /Invalid scheme specification/)
      end
    end
  end

  describe '.inline?' do
    it 'returns true for Hash specifications' do
      expect(described_class.inline?({ name: :test })).to be true
    end

    it 'returns false for Symbol specifications' do
      expect(described_class.inline?(:semantic)).to be false
    end

    it 'returns false for String specifications' do
      expect(described_class.inline?('semantic')).to be false
    end
  end

  describe '.reference?' do
    it 'returns true for Symbol specifications' do
      expect(described_class.reference?(:semantic)).to be true
    end

    it 'returns true for String specifications' do
      expect(described_class.reference?('semantic')).to be true
    end

    it 'returns false for Hash specifications' do
      expect(described_class.reference?({ name: :test })).to be false
    end
  end
end
