require_relative 'helper'
require 'reline/line_editor'

class Reline::LineEditor::Test < Reline::TestCase
  def test_range_subtract
    dummy_config = nil
    editor = Reline::LineEditor.new(dummy_config, 'ascii-8bit')
    base_ranges = [3...5, 4...10, 6...8, 12...15, 15...20]
    subtract_ranges = [5...7, 8...9, 11...13, 17...18, 18...19]
    expected_result = [3...5, 7...8, 9...10, 13...17, 19...20]
    assert_equal expected_result, editor.send(:range_subtract, base_ranges, subtract_ranges)
  end
end
