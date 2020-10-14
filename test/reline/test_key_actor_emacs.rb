require_relative 'helper'

class Reline::KeyActor::Emacs::Test < Reline::TestCase
  def setup
    Reline.send(:test_mode)
    @prompt = '> '
    @config = Reline::Config.new # Emacs mode is default
    Reline::HISTORY.instance_variable_set(:@config, @config)
    Reline::HISTORY.clear
    @encoding = (RELINE_TEST_ENCODING rescue Encoding.default_external)
    @line_editor = Reline::LineEditor.new(@config, @encoding)
    @line_editor.reset(@prompt, encoding: @encoding)
  end

  def test_ed_insert_one
    input_keys('a')
    assert_line('a')
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(1)
  end

  def test_ed_insert_two
    input_keys('ab')
    assert_line('ab')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
  end

  def test_ed_insert_mbchar_one
    input_keys('か')
    assert_line('か')
    assert_byte_pointer_size('か')
    assert_cursor(2)
    assert_cursor_max(2)
  end

  def test_ed_insert_mbchar_two
    input_keys('かき')
    assert_line('かき')
    assert_byte_pointer_size('かき')
    assert_cursor(4)
    assert_cursor_max(4)
  end

  def test_ed_insert_for_mbchar_by_plural_code_points
    input_keys("か\u3099")
    assert_line("か\u3099")
    assert_byte_pointer_size("か\u3099")
    assert_cursor(2)
    assert_cursor_max(2)
  end

  def test_ed_insert_for_plural_mbchar_by_plural_code_points
    input_keys("か\u3099き\u3099")
    assert_line("か\u3099き\u3099")
    assert_byte_pointer_size("か\u3099き\u3099")
    assert_cursor(4)
    assert_cursor_max(4)
  end

  def test_move_next_and_prev
    input_keys('abd')
    assert_byte_pointer_size('abd')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(3)
    input_keys("\C-f", false)
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    input_keys('c')
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(4)
    assert_line('abcd')
  end

  def test_move_next_and_prev_for_mbchar
    input_keys('かきけ')
    assert_byte_pointer_size('かきけ')
    assert_cursor(6)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('かき')
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('か')
    assert_cursor(2)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size('かき')
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys('く')
    assert_byte_pointer_size('かきく')
    assert_cursor(6)
    assert_cursor_max(8)
    assert_line('かきくけ')
  end

  def test_move_next_and_prev_for_mbchar_by_plural_code_points
    input_keys("か\u3099き\u3099け\u3099")
    assert_byte_pointer_size("か\u3099き\u3099け\u3099")
    assert_cursor(6)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size("か\u3099き\u3099")
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size("か\u3099")
    assert_cursor(2)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size("か\u3099き\u3099")
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys("く\u3099")
    assert_byte_pointer_size("か\u3099き\u3099く\u3099")
    assert_cursor(6)
    assert_cursor_max(8)
    assert_line("か\u3099き\u3099く\u3099け\u3099")
  end

  def test_move_to_beg_end
    input_keys('bcd')
    assert_byte_pointer_size('bcd')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(3)
    input_keys('a')
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(4)
    input_keys("\C-e", false)
    assert_byte_pointer_size('abcd')
    assert_cursor(4)
    assert_cursor_max(4)
    input_keys('e')
    assert_byte_pointer_size('abcde')
    assert_cursor(5)
    assert_cursor_max(5)
    assert_line('abcde')
  end

  def test_ed_newline_with_cr
    input_keys('ab')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
    refute(@line_editor.finished?)
    input_keys("\C-m", false)
    assert_line('ab')
    assert(@line_editor.finished?)
  end

  def test_ed_newline_with_lf
    input_keys('ab')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
    refute(@line_editor.finished?)
    input_keys("\C-j", false)
    assert_line('ab')
    assert(@line_editor.finished?)
  end

  def test_em_delete_prev_char
    input_keys('ab')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
    input_keys("\C-h", false)
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(1)
    assert_line('a')
  end

  def test_em_delete_prev_char_for_mbchar
    input_keys('かき')
    assert_byte_pointer_size('かき')
    assert_cursor(4)
    assert_cursor_max(4)
    input_keys("\C-h", false)
    assert_byte_pointer_size('か')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('か')
  end

  def test_em_delete_prev_char_for_mbchar_by_plural_code_points
    input_keys("か\u3099き\u3099")
    assert_byte_pointer_size("か\u3099き\u3099")
    assert_cursor(4)
    assert_cursor_max(4)
    input_keys("\C-h", false)
    assert_byte_pointer_size("か\u3099")
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line("か\u3099")
  end

  def test_ed_quoted_insert
    input_keys("ab\C-v\C-acd")
    assert_line("ab\C-acd")
    assert_byte_pointer_size("ab\C-acd")
    assert_cursor(6)
    assert_cursor_max(6)
    input_keys("\C-q\C-b")
    assert_line("ab\C-acd\C-b")
    assert_byte_pointer_size("ab\C-acd\C-b")
    assert_cursor(8)
    assert_cursor_max(8)
  end

  def test_ed_kill_line
    input_keys("\C-k", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
    input_keys('abc')
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-k", false)
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('abc')
    input_keys("\C-b\C-k", false)
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('ab')
  end

  def test_em_kill_line
    input_keys("\C-u", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
    input_keys('abc')
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-u", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
    input_keys('abc')
    input_keys("\C-b\C-u", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(1)
    assert_line('c')
    input_keys("\C-u", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(1)
    assert_line('c')
  end

  def test_ed_move_to_beg
    input_keys('abd')
    assert_byte_pointer_size('abd')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    input_keys('c')
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(4)
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(4)
    input_keys('012')
    assert_byte_pointer_size('012')
    assert_cursor(3)
    assert_cursor_max(7)
    assert_line('012abcd')
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(7)
    input_keys('ABC')
    assert_byte_pointer_size('ABC')
    assert_cursor(3)
    assert_cursor_max(10)
    assert_line('ABC012abcd')
    input_keys("\C-f" * 10 + "\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(10)
    input_keys('a')
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(11)
    assert_line('aABC012abcd')
  end

  def test_ed_move_to_beg_with_blank
    input_keys('  abc')
    assert_byte_pointer_size('  abc')
    assert_cursor(5)
    assert_cursor_max(5)
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
  end

  def test_ed_move_to_end
    input_keys('abd')
    assert_byte_pointer_size('abd')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    input_keys('c')
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(4)
    input_keys("\C-e", false)
    assert_byte_pointer_size('abcd')
    assert_cursor(4)
    assert_cursor_max(4)
    input_keys('012')
    assert_byte_pointer_size('abcd012')
    assert_cursor(7)
    assert_cursor_max(7)
    assert_line('abcd012')
    input_keys("\C-e", false)
    assert_byte_pointer_size('abcd012')
    assert_cursor(7)
    assert_cursor_max(7)
    input_keys('ABC')
    assert_byte_pointer_size('abcd012ABC')
    assert_cursor(10)
    assert_cursor_max(10)
    assert_line('abcd012ABC')
    input_keys("\C-b" * 10 + "\C-e", false)
    assert_byte_pointer_size('abcd012ABC')
    assert_cursor(10)
    assert_cursor_max(10)
    input_keys('a')
    assert_byte_pointer_size('abcd012ABCa')
    assert_cursor(11)
    assert_cursor_max(11)
    assert_line('abcd012ABCa')
  end

  def test_em_delete
    input_keys('ab')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(2)
    input_keys("\C-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(1)
    assert_line('b')
  end

  def test_em_delete_for_mbchar
    input_keys('かき')
    assert_byte_pointer_size('かき')
    assert_cursor(4)
    assert_cursor_max(4)
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(4)
    input_keys("\C-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(2)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(2)
    assert_line('き')
  end

  def test_em_delete_for_mbchar_by_plural_code_points
    input_keys("か\u3099き\u3099")
    assert_byte_pointer_size("か\u3099き\u3099")
    assert_cursor(4)
    assert_cursor_max(4)
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(4)
    input_keys("\C-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(2)
    assert_line("き\u3099")
  end

  def test_ed_clear_screen
    refute(@line_editor.instance_variable_get(:@cleared))
    input_keys("\C-l", false)
    assert(@line_editor.instance_variable_get(:@cleared))
  end

  def test_ed_clear_screen_with_inputed
    input_keys('abc')
    input_keys("\C-b", false)
    refute(@line_editor.instance_variable_get(:@cleared))
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    input_keys("\C-l", false)
    assert(@line_editor.instance_variable_get(:@cleared))
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    assert_line('abc')
  end

  def test_ed_delete_next_char
    input_keys('abc')
    assert_cursor(3)
    assert_cursor_max(3)
    @line_editor.input_key(Reline::Key.new(:key_delete, :key_delete, false))
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('abc')
  end

  def test_em_next_word
    assert_byte_pointer_size('')
    assert_cursor(0)
    input_keys('abc def{bbb}ccc')
    input_keys("\C-a\M-F", false)
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    input_keys("\M-F", false)
    assert_byte_pointer_size('abc def')
    assert_cursor(7)
    input_keys("\M-F", false)
    assert_byte_pointer_size('abc def{bbb')
    assert_cursor(11)
    input_keys("\M-F", false)
    assert_byte_pointer_size('abc def{bbb}ccc')
    assert_cursor(15)
    input_keys("\M-F", false)
    assert_byte_pointer_size('abc def{bbb}ccc')
    assert_cursor(15)
  end

  def test_em_next_word_for_mbchar
    assert_cursor(0)
    input_keys('あいう かきく{さしす}たちつ')
    input_keys("\C-a\M-F", false)
    assert_byte_pointer_size('あいう')
    assert_cursor(6)
    input_keys("\M-F", false)
    assert_byte_pointer_size('あいう かきく')
    assert_cursor(13)
    input_keys("\M-F", false)
    assert_byte_pointer_size('あいう かきく{さしす')
    assert_cursor(20)
    input_keys("\M-F", false)
    assert_byte_pointer_size('あいう かきく{さしす}たちつ')
    assert_cursor(27)
    input_keys("\M-F", false)
    assert_byte_pointer_size('あいう かきく{さしす}たちつ')
    assert_cursor(27)
  end

  def test_em_next_word_for_mbchar_by_plural_code_points
    assert_cursor(0)
    input_keys("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    input_keys("\C-a\M-F", false)
    assert_byte_pointer_size("あいう")
    assert_cursor(6)
    input_keys("\M-F", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099")
    assert_cursor(13)
    input_keys("\M-F", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{さしす")
    assert_cursor(20)
    input_keys("\M-F", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    assert_cursor(27)
    input_keys("\M-F", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    assert_cursor(27)
  end

  def test_em_prev_word
    input_keys('abc def{bbb}ccc')
    assert_byte_pointer_size('abc def{bbb}ccc')
    assert_cursor(15)
    input_keys("\M-B", false)
    assert_byte_pointer_size('abc def{bbb}')
    assert_cursor(12)
    input_keys("\M-B", false)
    assert_byte_pointer_size('abc def{')
    assert_cursor(8)
    input_keys("\M-B", false)
    assert_byte_pointer_size('abc ')
    assert_cursor(4)
    input_keys("\M-B", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    input_keys("\M-B", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
  end

  def test_em_prev_word_for_mbchar
    input_keys('あいう かきく{さしす}たちつ')
    assert_byte_pointer_size('あいう かきく{さしす}たちつ')
    assert_cursor(27)
    input_keys("\M-B", false)
    assert_byte_pointer_size('あいう かきく{さしす}')
    assert_cursor(21)
    input_keys("\M-B", false)
    assert_byte_pointer_size('あいう かきく{')
    assert_cursor(14)
    input_keys("\M-B", false)
    assert_byte_pointer_size('あいう ')
    assert_cursor(7)
    input_keys("\M-B", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    input_keys("\M-B", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
  end

  def test_em_prev_word_for_mbchar_by_plural_code_points
    input_keys("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    assert_cursor(27)
    input_keys("\M-B", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{さしす}")
    assert_cursor(21)
    input_keys("\M-B", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{")
    assert_cursor(14)
    input_keys("\M-B", false)
    assert_byte_pointer_size('あいう ')
    assert_cursor(7)
    input_keys("\M-B", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    input_keys("\M-B", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
  end

  def test_em_delete_next_word
    input_keys('abc def{bbb}ccc')
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(15)
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(12)
    assert_line(' def{bbb}ccc')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(8)
    assert_line('{bbb}ccc')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(4)
    assert_line('}ccc')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_em_delete_next_word_for_mbchar
    input_keys('あいう かきく{さしす}たちつ')
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(27)
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(21)
    assert_line(' かきく{さしす}たちつ')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(14)
    assert_line('{さしす}たちつ')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(7)
    assert_line('}たちつ')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_em_delete_next_word_for_mbchar_by_plural_code_points
    input_keys("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(27)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(27)
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(21)
    assert_line(" か\u3099き\u3099く\u3099{さしす}たちつ")
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(14)
    assert_line('{さしす}たちつ')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(7)
    assert_line('}たちつ')
    input_keys("\M-d", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_ed_delete_prev_word
    input_keys('abc def{bbb}ccc')
    assert_byte_pointer_size('abc def{bbb}ccc')
    assert_cursor(15)
    assert_cursor_max(15)
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('abc def{bbb}')
    assert_cursor(12)
    assert_cursor_max(12)
    assert_line('abc def{bbb}')
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('abc def{')
    assert_cursor(8)
    assert_cursor_max(8)
    assert_line('abc def{')
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('abc ')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('abc ')
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_ed_delete_prev_word_for_mbchar
    input_keys('あいう かきく{さしす}たちつ')
    assert_byte_pointer_size('あいう かきく{さしす}たちつ')
    assert_cursor(27)
    assert_cursor_max(27)
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('あいう かきく{さしす}')
    assert_cursor(21)
    assert_cursor_max(21)
    assert_line('あいう かきく{さしす}')
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('あいう かきく{')
    assert_cursor(14)
    assert_cursor_max(14)
    assert_line('あいう かきく{')
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('あいう ')
    assert_cursor(7)
    assert_cursor_max(7)
    assert_line('あいう ')
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_ed_delete_prev_word_for_mbchar_by_plural_code_points
    input_keys("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{さしす}たちつ")
    assert_cursor(27)
    assert_cursor_max(27)
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{さしす}")
    assert_cursor(21)
    assert_cursor_max(21)
    assert_line("あいう か\u3099き\u3099く\u3099{さしす}")
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size("あいう か\u3099き\u3099く\u3099{")
    assert_cursor(14)
    assert_cursor_max(14)
    assert_line("あいう か\u3099き\u3099く\u3099{")
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size("あいう ")
    assert_cursor(7)
    assert_cursor_max(7)
    assert_line('あいう ')
    input_keys("\M-\C-H", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_ed_transpose_chars
    input_keys('abc')
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(3)
    input_keys("\C-t", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(3)
    assert_line('abc')
    input_keys("\C-f\C-t", false)
    assert_byte_pointer_size('ba')
    assert_cursor(2)
    assert_cursor_max(3)
    assert_line('bac')
    input_keys("\C-t", false)
    assert_byte_pointer_size('bca')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('bca')
    input_keys("\C-t", false)
    assert_byte_pointer_size('bac')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('bac')
  end

  def test_ed_transpose_chars_for_mbchar
    input_keys('あかさ')
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    input_keys("\C-t", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    assert_line('あかさ')
    input_keys("\C-f\C-t", false)
    assert_byte_pointer_size('かあ')
    assert_cursor(4)
    assert_cursor_max(6)
    assert_line('かあさ')
    input_keys("\C-t", false)
    assert_byte_pointer_size('かさあ')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('かさあ')
    input_keys("\C-t", false)
    assert_byte_pointer_size('かあさ')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('かあさ')
  end

  def test_ed_transpose_chars_for_mbchar_by_plural_code_points
    input_keys("あか\u3099さ")
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    input_keys("\C-t", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    assert_line("あか\u3099さ")
    input_keys("\C-f\C-t", false)
    assert_byte_pointer_size("か\u3099あ")
    assert_cursor(4)
    assert_cursor_max(6)
    assert_line("か\u3099あさ")
    input_keys("\C-t", false)
    assert_byte_pointer_size("か\u3099さあ")
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line("か\u3099さあ")
    input_keys("\C-t", false)
    assert_byte_pointer_size("か\u3099あさ")
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line("か\u3099あさ")
  end

  def test_ed_transpose_words
    input_keys('abc def')
    assert_line('abc def')
    assert_byte_pointer_size('abc def')
    assert_cursor(7)
    assert_cursor_max(7)
    input_keys("\M-t", false)
    assert_line('def abc')
    assert_byte_pointer_size('def abc')
    assert_cursor(7)
    assert_cursor_max(7)
    input_keys("\C-a\C-k", false)
    input_keys(' abc  def   ')
    input_keys("\C-b" * 4, false)
    assert_line(' abc  def   ')
    assert_byte_pointer_size(' abc  de')
    assert_cursor(8)
    assert_cursor_max(12)
    input_keys("\M-t", false)
    assert_line(' def  abc   ')
    assert_byte_pointer_size(' def  abc')
    assert_cursor(9)
    assert_cursor_max(12)
    input_keys("\C-a\C-k", false)
    input_keys(' abc  def   ')
    input_keys("\C-b" * 6, false)
    assert_line(' abc  def   ')
    assert_byte_pointer_size(' abc  ')
    assert_cursor(6)
    assert_cursor_max(12)
    input_keys("\M-t", false)
    assert_line(' def  abc   ')
    assert_byte_pointer_size(' def  abc')
    assert_cursor(9)
    assert_cursor_max(12)
    input_keys("\M-t", false)
    assert_line(' abc     def')
    assert_byte_pointer_size(' abc     def')
    assert_cursor(12)
    assert_cursor_max(12)
  end

  def test_ed_transpose_words_for_mbchar
    input_keys('あいう かきく')
    assert_line('あいう かきく')
    assert_byte_pointer_size('あいう かきく')
    assert_cursor(13)
    assert_cursor_max(13)
    input_keys("\M-t", false)
    assert_line('かきく あいう')
    assert_byte_pointer_size('かきく あいう')
    assert_cursor(13)
    assert_cursor_max(13)
    input_keys("\C-a\C-k", false)
    input_keys(' あいう  かきく   ')
    input_keys("\C-b" * 4, false)
    assert_line(' あいう  かきく   ')
    assert_byte_pointer_size(' あいう  かき')
    assert_cursor(13)
    assert_cursor_max(18)
    input_keys("\M-t", false)
    assert_line(' かきく  あいう   ')
    assert_byte_pointer_size(' かきく  あいう')
    assert_cursor(15)
    assert_cursor_max(18)
    input_keys("\C-a\C-k", false)
    input_keys(' あいう  かきく   ')
    input_keys("\C-b" * 6, false)
    assert_line(' あいう  かきく   ')
    assert_byte_pointer_size(' あいう  ')
    assert_cursor(9)
    assert_cursor_max(18)
    input_keys("\M-t", false)
    assert_line(' かきく  あいう   ')
    assert_byte_pointer_size(' かきく  あいう')
    assert_cursor(15)
    assert_cursor_max(18)
    input_keys("\M-t", false)
    assert_line(' あいう     かきく')
    assert_byte_pointer_size(' あいう     かきく')
    assert_cursor(18)
    assert_cursor_max(18)
  end

  def test_ed_transpose_words_with_one_word
    input_keys('abc  ')
    assert_line('abc  ')
    assert_byte_pointer_size('abc  ')
    assert_cursor(5)
    assert_cursor_max(5)
    input_keys("\M-t", false)
    assert_line('abc  ')
    assert_byte_pointer_size('abc  ')
    assert_cursor(5)
    assert_cursor_max(5)
    input_keys("\C-b", false)
    assert_line('abc  ')
    assert_byte_pointer_size('abc ')
    assert_cursor(4)
    assert_cursor_max(5)
    input_keys("\M-t", false)
    assert_line('abc  ')
    assert_byte_pointer_size('abc ')
    assert_cursor(4)
    assert_cursor_max(5)
    input_keys("\C-b" * 2, false)
    assert_line('abc  ')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(5)
    input_keys("\M-t", false)
    assert_line('abc  ')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(5)
    input_keys("\M-t", false)
    assert_line('abc  ')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(5)
  end

  def test_ed_transpose_words_with_one_word_for_mbchar
    input_keys('あいう  ')
    assert_line('あいう  ')
    assert_byte_pointer_size('あいう  ')
    assert_cursor(8)
    assert_cursor_max(8)
    input_keys("\M-t", false)
    assert_line('あいう  ')
    assert_byte_pointer_size('あいう  ')
    assert_cursor(8)
    assert_cursor_max(8)
    input_keys("\C-b", false)
    assert_line('あいう  ')
    assert_byte_pointer_size('あいう ')
    assert_cursor(7)
    assert_cursor_max(8)
    input_keys("\M-t", false)
    assert_line('あいう  ')
    assert_byte_pointer_size('あいう ')
    assert_cursor(7)
    assert_cursor_max(8)
    input_keys("\C-b" * 2, false)
    assert_line('あいう  ')
    assert_byte_pointer_size('あい')
    assert_cursor(4)
    assert_cursor_max(8)
    input_keys("\M-t", false)
    assert_line('あいう  ')
    assert_byte_pointer_size('あい')
    assert_cursor(4)
    assert_cursor_max(8)
    input_keys("\M-t", false)
    assert_line('あいう  ')
    assert_byte_pointer_size('あい')
    assert_cursor(4)
    assert_cursor_max(8)
  end

  def test_ed_digit
    input_keys('0123')
    assert_byte_pointer_size('0123')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('0123')
  end

  def test_ed_next_and_prev_char
    input_keys('abc')
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(3)
    input_keys("\C-b", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(3)
    input_keys("\C-f", false)
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(3)
    input_keys("\C-f", false)
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(3)
    input_keys("\C-f", false)
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-f", false)
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(3)
  end

  def test_ed_next_and_prev_char_for_mbchar
    input_keys('あいう')
    assert_byte_pointer_size('あいう')
    assert_cursor(6)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('あい')
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('あ')
    assert_cursor(2)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size('あ')
    assert_cursor(2)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size('あい')
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size('あいう')
    assert_cursor(6)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size('あいう')
    assert_cursor(6)
    assert_cursor_max(6)
  end

  def test_ed_next_and_prev_char_for_mbchar_by_plural_code_points
    input_keys("か\u3099き\u3099く\u3099")
    assert_byte_pointer_size("か\u3099き\u3099く\u3099")
    assert_cursor(6)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size("か\u3099き\u3099")
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size("か\u3099")
    assert_cursor(2)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    input_keys("\C-b", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size("か\u3099")
    assert_cursor(2)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size("か\u3099き\u3099")
    assert_cursor(4)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size("か\u3099き\u3099く\u3099")
    assert_cursor(6)
    assert_cursor_max(6)
    input_keys("\C-f", false)
    assert_byte_pointer_size("か\u3099き\u3099く\u3099")
    assert_cursor(6)
    assert_cursor_max(6)
  end

  def test_em_capitol_case
    input_keys('abc def{bbb}ccc')
    input_keys("\C-a\M-c", false)
    assert_byte_pointer_size('Abc')
    assert_cursor(3)
    assert_cursor_max(15)
    assert_line('Abc def{bbb}ccc')
    input_keys("\M-c", false)
    assert_byte_pointer_size('Abc Def')
    assert_cursor(7)
    assert_cursor_max(15)
    assert_line('Abc Def{bbb}ccc')
    input_keys("\M-c", false)
    assert_byte_pointer_size('Abc Def{Bbb')
    assert_cursor(11)
    assert_cursor_max(15)
    assert_line('Abc Def{Bbb}ccc')
    input_keys("\M-c", false)
    assert_byte_pointer_size('Abc Def{Bbb}Ccc')
    assert_cursor(15)
    assert_cursor_max(15)
    assert_line('Abc Def{Bbb}Ccc')
  end

  def test_em_capitol_case_with_complex_example
    input_keys('{}#*    AaA!!!cCc   ')
    input_keys("\C-a\M-c", false)
    assert_byte_pointer_size('{}#*    Aaa')
    assert_cursor(11)
    assert_cursor_max(20)
    assert_line('{}#*    Aaa!!!cCc   ')
    input_keys("\M-c", false)
    assert_byte_pointer_size('{}#*    Aaa!!!Ccc')
    assert_cursor(17)
    assert_cursor_max(20)
    assert_line('{}#*    Aaa!!!Ccc   ')
    input_keys("\M-c", false)
    assert_byte_pointer_size('{}#*    Aaa!!!Ccc   ')
    assert_cursor(20)
    assert_cursor_max(20)
    assert_line('{}#*    Aaa!!!Ccc   ')
  end

  def test_em_lower_case
    input_keys('AbC def{bBb}CCC')
    input_keys("\C-a\M-l", false)
    assert_byte_pointer_size('abc')
    assert_cursor(3)
    assert_cursor_max(15)
    assert_line('abc def{bBb}CCC')
    input_keys("\M-l", false)
    assert_byte_pointer_size('abc def')
    assert_cursor(7)
    assert_cursor_max(15)
    assert_line('abc def{bBb}CCC')
    input_keys("\M-l", false)
    assert_byte_pointer_size('abc def{bbb')
    assert_cursor(11)
    assert_cursor_max(15)
    assert_line('abc def{bbb}CCC')
    input_keys("\M-l", false)
    assert_byte_pointer_size('abc def{bbb}ccc')
    assert_cursor(15)
    assert_cursor_max(15)
    assert_line('abc def{bbb}ccc')
  end

  def test_em_lower_case_with_complex_example
    input_keys('{}#*    AaA!!!cCc   ')
    input_keys("\C-a\M-l", false)
    assert_byte_pointer_size('{}#*    aaa')
    assert_cursor(11)
    assert_cursor_max(20)
    assert_line('{}#*    aaa!!!cCc   ')
    input_keys("\M-l", false)
    assert_byte_pointer_size('{}#*    aaa!!!ccc')
    assert_cursor(17)
    assert_cursor_max(20)
    assert_line('{}#*    aaa!!!ccc   ')
    input_keys("\M-l", false)
    assert_byte_pointer_size('{}#*    aaa!!!ccc   ')
    assert_cursor(20)
    assert_cursor_max(20)
    assert_line('{}#*    aaa!!!ccc   ')
  end

  def test_em_upper_case
    input_keys('AbC def{bBb}CCC')
    input_keys("\C-a\M-u", false)
    assert_byte_pointer_size('ABC')
    assert_cursor(3)
    assert_cursor_max(15)
    assert_line('ABC def{bBb}CCC')
    input_keys("\M-u", false)
    assert_byte_pointer_size('ABC DEF')
    assert_cursor(7)
    assert_cursor_max(15)
    assert_line('ABC DEF{bBb}CCC')
    input_keys("\M-u", false)
    assert_byte_pointer_size('ABC DEF{BBB')
    assert_cursor(11)
    assert_cursor_max(15)
    assert_line('ABC DEF{BBB}CCC')
    input_keys("\M-u", false)
    assert_byte_pointer_size('ABC DEF{BBB}CCC')
    assert_cursor(15)
    assert_cursor_max(15)
    assert_line('ABC DEF{BBB}CCC')
  end

  def test_em_upper_case_with_complex_example
    input_keys('{}#*    AaA!!!cCc   ')
    input_keys("\C-a\M-u", false)
    assert_byte_pointer_size('{}#*    AAA')
    assert_cursor(11)
    assert_cursor_max(20)
    assert_line('{}#*    AAA!!!cCc   ')
    input_keys("\M-u", false)
    assert_byte_pointer_size('{}#*    AAA!!!CCC')
    assert_cursor(17)
    assert_cursor_max(20)
    assert_line('{}#*    AAA!!!CCC   ')
    input_keys("\M-u", false)
    assert_byte_pointer_size('{}#*    AAA!!!CCC   ')
    assert_cursor(20)
    assert_cursor_max(20)
    assert_line('{}#*    AAA!!!CCC   ')
  end

  def test_em_delete_or_list
    @line_editor.completion_proc = proc { |word|
      %w{
        foo_foo
        foo_bar
        foo_baz
        qux
      }.map { |i|
        i.encode(@encoding)
      }
    }
    input_keys('fooo')
    assert_byte_pointer_size('fooo')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('fooo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-b", false)
    assert_byte_pointer_size('foo')
    assert_cursor(3)
    assert_cursor_max(4)
    assert_line('fooo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    @line_editor.input_key(Reline::Key.new(:em_delete_or_list, :em_delete_or_list, false))
    assert_byte_pointer_size('foo')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('foo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    @line_editor.input_key(Reline::Key.new(:em_delete_or_list, :em_delete_or_list, false))
    assert_byte_pointer_size('foo')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('foo')
    assert_equal(%w{foo_foo foo_bar foo_baz}, @line_editor.instance_variable_get(:@menu_info).list)
  end

  def test_completion_duplicated_list
    @line_editor.completion_proc = proc { |word|
      %w{
        foo_foo
        foo_foo
        foo_bar
      }.map { |i|
        i.encode(@encoding)
      }
    }
    input_keys('foo_')
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(%w{foo_foo foo_bar}, @line_editor.instance_variable_get(:@menu_info).list)
  end

  def test_completion
    @line_editor.completion_proc = proc { |word|
      %w{
        foo_foo
        foo_bar
        foo_baz
        qux
      }.map { |i|
        i.encode(@encoding)
      }
    }
    input_keys('fo')
    assert_byte_pointer_size('fo')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('fo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(%w{foo_foo foo_bar foo_baz}, @line_editor.instance_variable_get(:@menu_info).list)
    input_keys('a')
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_a')
    assert_cursor(5)
    assert_cursor_max(5)
    assert_line('foo_a')
    input_keys("\C-h", false)
    input_keys('b')
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_ba')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('foo_ba')
  end

  def test_completion_with_indent
    @line_editor.completion_proc = proc { |word|
      %w{
        foo_foo
        foo_bar
        foo_baz
        qux
      }.map { |i|
        i.encode(@encoding)
      }
    }
    input_keys('  fo')
    assert_byte_pointer_size('  fo')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('  fo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('  foo_')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('  foo_')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('  foo_')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('  foo_')
    assert_equal(%w{foo_foo foo_bar foo_baz}, @line_editor.instance_variable_get(:@menu_info).list)
  end

  def test_completion_with_indent_and_completer_quote_characters
    @line_editor.completion_proc = proc { |word|
      %w{
        "".foo_foo
        "".foo_bar
        "".foo_baz
        "".qux
      }.map { |i|
        i.encode(@encoding)
      }
    }
    input_keys('  "".fo')
    assert_byte_pointer_size('  "".fo')
    assert_cursor(7)
    assert_cursor_max(7)
    assert_line('  "".fo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('  "".foo_')
    assert_cursor(9)
    assert_cursor_max(9)
    assert_line('  "".foo_')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('  "".foo_')
    assert_cursor(9)
    assert_cursor_max(9)
    assert_line('  "".foo_')
    assert_equal(%w{"".foo_foo "".foo_bar "".foo_baz}, @line_editor.instance_variable_get(:@menu_info).list)
  end

  def test_completion_with_perfect_match
    @line_editor.completion_proc = proc { |word|
      %w{
        foo
        foo_bar
      }.map { |i|
        i.encode(@encoding)
      }
    }
    matched = nil
    @line_editor.dig_perfect_match_proc = proc { |m|
      matched = m
    }
    input_keys('fo')
    assert_byte_pointer_size('fo')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('fo')
    assert_equal(Reline::LineEditor::CompletionState::NORMAL, @line_editor.instance_variable_get(:@completion_state))
    assert_equal(nil, matched)
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('foo')
    assert_equal(Reline::LineEditor::CompletionState::MENU_WITH_PERFECT_MATCH, @line_editor.instance_variable_get(:@completion_state))
    assert_equal(nil, matched)
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('foo')
    assert_equal(Reline::LineEditor::CompletionState::PERFECT_MATCH, @line_editor.instance_variable_get(:@completion_state))
    assert_equal(nil, matched)
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('foo')
    assert_equal(Reline::LineEditor::CompletionState::PERFECT_MATCH, @line_editor.instance_variable_get(:@completion_state))
    assert_equal('foo', matched)
    matched = nil
    input_keys('_')
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_bar')
    assert_cursor(7)
    assert_cursor_max(7)
    assert_line('foo_bar')
    assert_equal(Reline::LineEditor::CompletionState::MENU_WITH_PERFECT_MATCH, @line_editor.instance_variable_get(:@completion_state))
    assert_equal(nil, matched)
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_bar')
    assert_cursor(7)
    assert_cursor_max(7)
    assert_line('foo_bar')
    assert_equal(Reline::LineEditor::CompletionState::PERFECT_MATCH, @line_editor.instance_variable_get(:@completion_state))
    assert_equal(nil, matched)
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_bar')
    assert_cursor(7)
    assert_cursor_max(7)
    assert_line('foo_bar')
    assert_equal(Reline::LineEditor::CompletionState::PERFECT_MATCH, @line_editor.instance_variable_get(:@completion_state))
    assert_equal('foo_bar', matched)
  end

  def test_completion_with_completion_ignore_case
    @line_editor.completion_proc = proc { |word|
      %w{
        foo_foo
        foo_bar
        Foo_baz
        qux
      }.map { |i|
        i.encode(@encoding)
      }
    }
    input_keys('fo')
    assert_byte_pointer_size('fo')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('fo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(%w{foo_foo foo_bar}, @line_editor.instance_variable_get(:@menu_info).list)
    @config.completion_ignore_case = true
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(%w{foo_foo foo_bar Foo_baz}, @line_editor.instance_variable_get(:@menu_info).list)
    input_keys('a')
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_a')
    assert_cursor(5)
    assert_cursor_max(5)
    assert_line('foo_a')
    input_keys("\C-h", false)
    input_keys('b')
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_ba')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('foo_ba')
  end

  def test_completion_in_middle_of_line
    @line_editor.completion_proc = proc { |word|
      %w{
        foo_foo
        foo_bar
        foo_baz
        qux
      }.map { |i|
        i.encode(@encoding)
      }
    }
    input_keys('abcde fo ABCDE')
    assert_line('abcde fo ABCDE')
    input_keys("\C-b" * 6 + "\C-i", false)
    assert_byte_pointer_size('abcde foo_')
    assert_cursor(10)
    assert_cursor_max(16)
    assert_line('abcde foo_ ABCDE')
    input_keys("\C-b" * 2 + "\C-i", false)
    assert_byte_pointer_size('abcde foo_')
    assert_cursor(10)
    assert_cursor_max(18)
    assert_line('abcde foo_o_ ABCDE')
  end

  def test_completion_with_nil_value
    @line_editor.completion_proc = proc { |word|
      %w{
        foo_foo
        foo_bar
        Foo_baz
        qux
      }.map { |i|
        i.encode(@encoding)
      }.prepend(nil)
    }
    @config.completion_ignore_case = true
    input_keys('fo')
    assert_byte_pointer_size('fo')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('fo')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(nil, @line_editor.instance_variable_get(:@menu_info))
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_')
    assert_cursor(4)
    assert_cursor_max(4)
    assert_line('foo_')
    assert_equal(%w{foo_foo foo_bar Foo_baz}, @line_editor.instance_variable_get(:@menu_info).list)
    input_keys('a')
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_a')
    assert_cursor(5)
    assert_cursor_max(5)
    assert_line('foo_a')
    input_keys("\C-h", false)
    input_keys('b')
    input_keys("\C-i", false)
    assert_byte_pointer_size('foo_ba')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('foo_ba')
  end

  def test_em_kill_region
    input_keys('abc   def{bbb}ccc   ddd   ')
    assert_byte_pointer_size('abc   def{bbb}ccc   ddd   ')
    assert_cursor(26)
    assert_cursor_max(26)
    assert_line('abc   def{bbb}ccc   ddd   ')
    input_keys("\C-w", false)
    assert_byte_pointer_size('abc   def{bbb}ccc   ')
    assert_cursor(20)
    assert_cursor_max(20)
    assert_line('abc   def{bbb}ccc   ')
    input_keys("\C-w", false)
    assert_byte_pointer_size('abc   ')
    assert_cursor(6)
    assert_cursor_max(6)
    assert_line('abc   ')
    input_keys("\C-w", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
    input_keys("\C-w", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_em_kill_region_mbchar
    input_keys('あ   い   う{う}う   ')
    assert_byte_pointer_size('あ   い   う{う}う   ')
    assert_cursor(21)
    assert_cursor_max(21)
    assert_line('あ   い   う{う}う   ')
    input_keys("\C-w", false)
    assert_byte_pointer_size('あ   い   ')
    assert_cursor(10)
    assert_cursor_max(10)
    assert_line('あ   い   ')
    input_keys("\C-w", false)
    assert_byte_pointer_size('あ   ')
    assert_cursor(5)
    assert_cursor_max(5)
    assert_line('あ   ')
    input_keys("\C-w", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

  def test_vi_search_prev
    Reline::HISTORY.concat(%w{abc 123 AAA})
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-ra\C-j")
    assert_line('abc')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(3)
  end

  def test_larger_histories_than_history_size
    history_size = @config.history_size
    @config.history_size = 2
    Reline::HISTORY.concat(%w{abc 123 AAA})
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-p")
    assert_line('AAA')
    assert_byte_pointer_size('AAA')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-p")
    assert_line('123')
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(3)
    input_keys("\C-p")
    assert_line('123')
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(3)
  ensure
    @config.history_size = history_size
  end

  def test_search_history_to_back
    Reline::HISTORY.concat([
      '1235', # old
      '12aa',
      '1234' # new
    ])
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r123")
    assert_line('1234')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0) # doesn't determine yet
    input_keys("\C-ha")
    assert_line('12aa')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-h3")
    assert_line('1235')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
  end

  def test_search_history_to_front
    Reline::HISTORY.concat([
      '1235', # old
      '12aa',
      '1234' # new
    ])
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-s123")
    assert_line('1235')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0) # doesn't determine yet
    input_keys("\C-ha")
    assert_line('12aa')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-h3")
    assert_line('1234')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
  end

  def test_search_history_front_and_back
    Reline::HISTORY.concat([
      '1235', # old
      '12aa',
      '1234' # new
    ])
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-s12")
    assert_line('1235')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0) # doesn't determine yet
    input_keys("\C-s")
    assert_line('12aa')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r")
    assert_line('12aa')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r")
    assert_line('1235')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
  end

  def test_search_history_back_and_front
    Reline::HISTORY.concat([
      '1235', # old
      '12aa',
      '1234' # new
    ])
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r12")
    assert_line('1234')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0) # doesn't determine yet
    input_keys("\C-r")
    assert_line('12aa')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-s")
    assert_line('12aa')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-s")
    assert_line('1234')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
  end

  def test_search_history_to_back_in_the_middle_of_histories
    Reline::HISTORY.concat([
      '1235', # old
      '12aa',
      '1234' # new
    ])
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-p\C-p")
    assert_line('12aa')
    assert_byte_pointer_size('12aa')
    assert_cursor(4)
    assert_cursor_max(4)
    input_keys("\C-r123")
    assert_line('1235')
    assert_byte_pointer_size('1235')
    assert_cursor(4)
    assert_cursor_max(4)
  end

  def test_search_history_twice
    Reline::HISTORY.concat([
      '1235', # old
      '12aa',
      '1234' # new
    ])
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r123")
    assert_line('1234')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0) # doesn't determine yet
    input_keys("\C-r")
    assert_line('1235')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
  end

  def test_search_history_by_last_determined
    Reline::HISTORY.concat([
      '1235', # old
      '12aa',
      '1234' # new
    ])
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r123")
    assert_line('1234')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0) # doesn't determine yet
    input_keys("\C-j")
    assert_line('1234')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(4)
    input_keys("\C-k") # delete
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r")
    assert_line('')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    input_keys("\C-r")
    assert_line('1235')
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
  end

  def test_em_set_mark_and_em_exchange_mark
    input_keys('aaa bbb ccc ddd')
    assert_byte_pointer_size('aaa bbb ccc ddd')
    assert_cursor(15)
    assert_cursor_max(15)
    assert_line('aaa bbb ccc ddd')
    input_keys("\C-a\M-F\M-F", false)
    assert_byte_pointer_size('aaa bbb')
    assert_cursor(7)
    assert_cursor_max(15)
    assert_line('aaa bbb ccc ddd')
    assert_equal(nil, @line_editor.instance_variable_get(:@mark_pointer))
    input_keys("\x00", false) # C-Space
    assert_byte_pointer_size('aaa bbb')
    assert_cursor(7)
    assert_cursor_max(15)
    assert_line('aaa bbb ccc ddd')
    assert_equal([7, 0], @line_editor.instance_variable_get(:@mark_pointer))
    input_keys("\C-a", false)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(15)
    assert_line('aaa bbb ccc ddd')
    assert_equal([7, 0], @line_editor.instance_variable_get(:@mark_pointer))
    input_key_by_symbol(:em_exchange_mark)
    assert_byte_pointer_size('aaa bbb')
    assert_cursor(7)
    assert_cursor_max(15)
    assert_line('aaa bbb ccc ddd')
    assert_equal([0, 0], @line_editor.instance_variable_get(:@mark_pointer))
  end

  def test_modify_lines_with_wrong_rs
    verbose, $VERBOSE = $VERBOSE, nil
    original_global_slash = $/
    $/ = 'b'
    $VERBOSE = verbose
    @line_editor.output_modifier_proc = proc { |output| Reline::Unicode.escape_for_print(output) }
    input_keys("abcdef\n")
    result = @line_editor.__send__(:modify_lines, @line_editor.whole_lines)
    $/ = nil
    assert_equal(['abcdef'], result)
  ensure
    $VERBOSE = nil
    $/ = original_global_slash
    $VERBOSE = verbose
  end

  def test_ed_search_prev_history
    Reline::HISTORY.concat([
      '12356', # old
      '12aaa',
      '12345' # new
    ])
    input_keys('123')
    # The ed_search_prev_history doesn't have default binding
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12345')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12356')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12356')
  end

  def test_ed_search_prev_history_with_empty
    Reline::HISTORY.concat([
      '12356', # old
      '12aaa',
      '12345' # new
    ])
    # The ed_search_prev_history doesn't have default binding
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12345')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12aaa')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12356')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12356')
  end

  def test_ed_search_prev_history_without_match
    Reline::HISTORY.concat([
      '12356', # old
      '12aaa',
      '12345' # new
    ])
    input_keys('ABC')
    # The ed_search_prev_history doesn't have default binding
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('ABC')
    assert_cursor(3)
    assert_cursor_max(3)
    assert_line('ABC')
  end

  def test_ed_search_next_history
    Reline::HISTORY.concat([
      '12356', # old
      '12aaa',
      '12345' # new
    ])
    input_keys('123')
    # The ed_search_prev_history and ed_search_next_history doesn't have default binding
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12345')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12356')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12356')
    @line_editor.__send__(:ed_search_next_history, "\C-n".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12345')
    @line_editor.__send__(:ed_search_next_history, "\C-n".ord)
    assert_byte_pointer_size('123')
    assert_cursor(3)
    assert_cursor_max(5)
    assert_line('12345')
  end

  def test_ed_search_next_history_with_empty
    Reline::HISTORY.concat([
      '12356', # old
      '12aaa',
      '12345' # new
    ])
    # The ed_search_prev_history and ed_search_next_history doesn't have default binding
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12345')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12aaa')
    @line_editor.__send__(:ed_search_prev_history, "\C-p".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12356')
    @line_editor.__send__(:ed_search_next_history, "\C-n".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12aaa')
    @line_editor.__send__(:ed_search_next_history, "\C-n".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(5)
    assert_line('12345')
    @line_editor.__send__(:ed_search_next_history, "\C-n".ord)
    assert_byte_pointer_size('')
    assert_cursor(0)
    assert_cursor_max(0)
    assert_line('')
  end

=begin # TODO: move KeyStroke instance from Reline to LineEditor
  def test_key_delete
    input_keys('ab')
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('ab')
    [27, 91, 51, 126].each do |key|
      @line_editor.input_key(key)
    end
    assert_byte_pointer_size('ab')
    assert_cursor(2)
    assert_cursor_max(2)
    assert_line('ab')
    input_keys("\C-b")
    [27, 91, 51, 126].each do |key|
      @line_editor.input_key(key)
    end
    assert_byte_pointer_size('a')
    assert_cursor(1)
    assert_cursor_max(1)
    assert_line('a')
  end
=end
end
