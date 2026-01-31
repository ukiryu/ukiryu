# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Inkscape Tool Profile' do
  include ToolHelper

  before(:each) { @temp_dir = create_temp_dir }

  after(:each) do
    # Clean up temp directory
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  describe 'tool availability' do
    it 'detects Inkscape on the system' do
      skip_unless_tool_available(:inkscape)

      tool = get_tool(:inkscape)
      expect(tool.available?).to be true
      expect(tool.executable).to match(/inkscape|Inkscape/)
      expect(tool.version).to match(/\d+\.\d+/)
    end
  end

  describe 'export command' do
    before(:each) { skip_unless_tool_available(:inkscape) }

    it 'exports SVG to PNG' do
      input = File.join(@temp_dir, 'input.svg')
      output = File.join(@temp_dir, 'output.png')

      create_test_svg(input)

      tool = get_tool(:inkscape)
      result = tool.execute(:export, execution_timeout: 30, inputs: [input], output: output, format: :png)

      expect(result.success?).to be true
      expect(result.exit_code).to eq(0)
      expect(File.exist?(output)).to be true
    end

    it 'exports SVG to PDF' do
      input = File.join(@temp_dir, 'input.svg')
      output = File.join(@temp_dir, 'output.pdf')

      create_test_svg(input)

      tool = get_tool(:inkscape)
      result = tool.execute(:export, execution_timeout: 30, inputs: [input], output: output, format: :pdf)

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end

    it 'exports with custom DPI' do
      input = File.join(@temp_dir, 'input.svg')
      output = File.join(@temp_dir, 'output.png')

      create_test_svg(input)

      tool = get_tool(:inkscape)
      result = tool.execute(:export, execution_timeout: 30, inputs: [input], output: output, format: :png, dpi: 300)

      expect(result.success?).to be true
      expect(File.exist?(output)).to be true
    end
  end

  # Helper method to create a simple test SVG file
  def create_test_svg(path)
    svg_content = <<~SVG
      <?xml version="1.0" encoding="UTF-8"?>
      <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <rect width="100" height="100" fill="blue"/>
        <circle cx="50" cy="50" r="25" fill="red"/>
      </svg>
    SVG

    File.write(path, svg_content)
  end
end
