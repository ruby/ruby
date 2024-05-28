require_relative 'helper'
require 'reline/line_editor'
require 'stringio'

class Reline::LineEditor
  class RenderLineDifferentialTest < Reline::TestCase
    module TestIO
      RESET_COLOR = "\e[0m"

      def self.move_cursor_column(col)
        @output << "[COL_#{col}]"
      end

      def self.erase_after_cursor
        @output << '[ERASE]'
      end
    end

    def setup
      verbose, $VERBOSE = $VERBOSE, nil
      @line_editor = Reline::LineEditor.new(nil, Encoding::UTF_8)
      @original_iogate = Reline::IOGate
      @output = StringIO.new
      @line_editor.instance_variable_set(:@screen_size, [24, 80])
      @line_editor.instance_variable_set(:@output, @output)
      Reline.send(:remove_const, :IOGate)
      Reline.const_set(:IOGate, TestIO)
      Reline::IOGate.instance_variable_set(:@output, @output)
    ensure
      $VERBOSE = verbose
    end

    def assert_output(expected)
      @output.reopen(+'')
      yield
      actual = @output.string
      assert_equal(expected, actual.gsub("\e[0m", ''))
    end

    def teardown
      Reline.send(:remove_const, :IOGate)
      Reline.const_set(:IOGate, @original_iogate)
    end

    def test_line_increase_decrease
      assert_output '[COL_0]bb' do
        @line_editor.render_line_differential([[0, 1, 'a']], [[0, 2, 'bb']])
      end

      assert_output '[COL_0]b[COL_1][ERASE]' do
        @line_editor.render_line_differential([[0, 2, 'aa']], [[0, 1, 'b']])
      end
    end

    def test_dialog_appear_disappear
      assert_output '[COL_3]dialog' do
        @line_editor.render_line_differential([[0, 1, 'a']], [[0, 1, 'a'], [3, 6, 'dialog']])
      end

      assert_output '[COL_3]dialog' do
        @line_editor.render_line_differential([[0, 10, 'a' * 10]], [[0, 10, 'a' * 10], [3, 6, 'dialog']])
      end

      assert_output '[COL_1][ERASE]' do
        @line_editor.render_line_differential([[0, 1, 'a'], [3, 6, 'dialog']], [[0, 1, 'a']])
      end

      assert_output '[COL_3]aaaaaa' do
        @line_editor.render_line_differential([[0, 10, 'a' * 10], [3, 6, 'dialog']], [[0, 10, 'a' * 10]])
      end
    end

    def test_dialog_change
      assert_output '[COL_3]DIALOG' do
        @line_editor.render_line_differential([[0, 2, 'a'], [3, 6, 'dialog']], [[0, 2, 'a'], [3, 6, 'DIALOG']])
      end

      assert_output '[COL_3]DIALOG' do
        @line_editor.render_line_differential([[0, 10, 'a' * 10], [3, 6, 'dialog']], [[0, 10, 'a' * 10], [3, 6, 'DIALOG']])
      end
    end

    def test_update_under_dialog
      assert_output '[COL_0]b[COL_1] ' do
        @line_editor.render_line_differential([[0, 2, 'aa'], [4, 6, 'dialog']], [[0, 1, 'b'], [4, 6, 'dialog']])
      end

      assert_output '[COL_0]bbb[COL_9]b' do
        @line_editor.render_line_differential([[0, 10, 'a' * 10], [3, 6, 'dialog']], [[0, 10, 'b' * 10], [3, 6, 'dialog']])
      end

      assert_output '[COL_0]b[COL_1]  [COL_9][ERASE]' do
        @line_editor.render_line_differential([[0, 10, 'a' * 10], [3, 6, 'dialog']], [[0, 1, 'b'], [3, 6, 'dialog']])
      end
    end

    def test_dialog_move
      assert_output '[COL_3]dialog[COL_9][ERASE]' do
        @line_editor.render_line_differential([[0, 1, 'a'], [4, 6, 'dialog']], [[0, 1, 'a'], [3, 6, 'dialog']])
      end

      assert_output '[COL_4] [COL_5]dialog' do
        @line_editor.render_line_differential([[0, 1, 'a'], [4, 6, 'dialog']], [[0, 1, 'a'], [5, 6, 'dialog']])
      end

      assert_output '[COL_2]dialog[COL_8]a' do
        @line_editor.render_line_differential([[0, 10, 'a' * 10], [3, 6, 'dialog']], [[0, 10, 'a' * 10], [2, 6, 'dialog']])
      end

      assert_output '[COL_2]a[COL_3]dialog' do
        @line_editor.render_line_differential([[0, 10, 'a' * 10], [2, 6, 'dialog']], [[0, 10, 'a' * 10], [3, 6, 'dialog']])
      end
    end

    def test_multibyte
      base = [0, 12, '一二三一二三']
      left = [0, 3, 'LLL']
      right = [9, 3, 'RRR']
      front = [3, 6, 'FFFFFF']
      # 一 FFFFFF 三
      # 一二三一二三
      assert_output '[COL_2]二三一二' do
        @line_editor.render_line_differential([base, front], [base, nil])
      end

      # LLLFFFFFF 三
      # LLL 三一二三
      assert_output '[COL_3] 三一二' do
        @line_editor.render_line_differential([base, left, front], [base, left, nil])
      end

      # 一 FFFFFFRRR
      # 一二三一 RRR
      assert_output '[COL_2]二三一 ' do
        @line_editor.render_line_differential([base, right, front], [base, right, nil])
      end

      # LLLFFFFFFRRR
      # LLL 三一 RRR
      assert_output '[COL_3] 三一 ' do
        @line_editor.render_line_differential([base, left, right, front], [base, left, right, nil])
      end
    end

    def test_complicated
      state_a = [nil, [19, 7, 'bbbbbbb'], [15, 8, 'cccccccc'], [10, 5, 'ddddd'], [18, 4, 'eeee'], [1, 3, 'fff'], [17, 2, 'gg'], [7, 1, 'h']]
      state_b = [[5, 9, 'aaaaaaaaa'], nil, [15, 8, 'cccccccc'], nil, [18, 4, 'EEEE'], [25, 4, 'ffff'], [17, 2, 'gg'], [2, 2, 'hh']]
      # state_a: " fff   h  dddddccggeeecbbb"
      # state_b: "  hh aaaaaaaaa ccggEEEc  ffff"

      assert_output '[COL_1] [COL_2]hh[COL_5]aaaaaaaaa[COL_14] [COL_19]EEE[COL_23]  [COL_25]ffff' do
        @line_editor.render_line_differential(state_a, state_b)
      end

      assert_output '[COL_1]fff[COL_5]  [COL_7]h[COL_8]  [COL_10]ddddd[COL_19]eee[COL_23]bbb[COL_26][ERASE]' do
        @line_editor.render_line_differential(state_b, state_a)
      end
    end
  end

  def test_menu_info_format
    list = %w[aa b c d e f g hhh i j k]
    col3 = [
      'aa   e    i',
      'b    f    j',
      'c    g    k',
      'd    hhh'
    ]
    col2 = [
      'aa   g',
      'b    hhh',
      'c    i',
      'd    j',
      'e    k',
      'f'
    ]
    assert_equal(col3, Reline::LineEditor::MenuInfo.new(list).lines(19))
    assert_equal(col3, Reline::LineEditor::MenuInfo.new(list).lines(15))
    assert_equal(col2, Reline::LineEditor::MenuInfo.new(list).lines(14))
    assert_equal(col2, Reline::LineEditor::MenuInfo.new(list).lines(10))
    assert_equal(list, Reline::LineEditor::MenuInfo.new(list).lines(9))
    assert_equal(list, Reline::LineEditor::MenuInfo.new(list).lines(0))
    assert_equal([], Reline::LineEditor::MenuInfo.new([]).lines(10))
  end
end
