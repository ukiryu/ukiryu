# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ToolHelper do
  subject(:probe) { helper.inkscape_export_available? }

  let(:helper) { Object.new.extend(described_class) }
  let(:tool) { instance_double(Ukiryu::Tool, available?: true, executable: '/test/inkscape') }

  before do
    allow(helper).to receive(:get_tool).with(:inkscape).and_return(tool)
  end

  describe '#inkscape_export_available?' do
    it 'rejects a missing executable without attempting an export' do
      allow(tool).to receive(:available?).and_return(false)
      expect(helper).not_to receive(:system)

      expect(probe).to be false
    end

    it 'rejects an unavailable tool profile' do
      allow(helper).to receive(:get_tool).with(:inkscape).and_raise(Ukiryu::Errors::ToolNotFoundError)

      expect(probe).to be false
    end

    it 'exports a tiny SVG and removes the temporary directory' do
      input_path = nil
      allow(helper).to receive(:system) do |executable, format, output, input, **options|
        expect(executable).to eq('/test/inkscape')
        expect(format).to eq('--export-type=png')
        expect(options).to eq(out: File::NULL, err: File::NULL)
        expect(File.read(input)).to include('<svg', '<rect')
        input_path = input
        File.binwrite(output.delete_prefix('--export-filename='), "\x89PNG\r\n\x1a\n")
        true
      end

      expect(probe).to be true
      expect(Dir.exist?(File.dirname(input_path))).to be false
    end

    it 'rejects a successful exit without an output file' do
      allow(helper).to receive(:system).and_return(true)

      expect(probe).to be false
    end

    it 'rejects an empty output file' do
      allow(helper).to receive(:system) do |_, _, output, *_|
        File.write(output.delete_prefix('--export-filename='), '')
        true
      end

      expect(probe).to be false
    end

    it 'rejects a failed conversion even when it leaves an output file' do
      allow(helper).to receive(:system) do |_, _, output, *_|
        File.write(output.delete_prefix('--export-filename='), 'partial PNG')
        false
      end

      expect(probe).to be false
    end
  end
end
