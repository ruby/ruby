require_relative 'helper'
require 'reline'

class Reline::ANSI::WithoutTerminfoTest < Reline::TestCase
  def setup
    Reline.send(:test_mode, ansi: true)
    @config = Reline::Config.new
    Reline.core.io_gate.set_default_key_bindings(@config, allow_terminfo: false)
  end

  def teardown
    Reline.test_reset
  end

  def test_home
    assert_key_binding("\e[1~", :ed_move_to_beg) # Console (80x25)
    assert_key_binding("\e[H", :ed_move_to_beg) # KDE
    assert_key_binding("\e[7~", :ed_move_to_beg) # urxvt / exoterm
    assert_key_binding("\eOH", :ed_move_to_beg) # GNOME
  end

  def test_end
    assert_key_binding("\e[4~", :ed_move_to_end) # Console (80x25)
    assert_key_binding("\e[F", :ed_move_to_end) # KDE
    assert_key_binding("\e[8~", :ed_move_to_end) # urxvt / exoterm
    assert_key_binding("\eOF", :ed_move_to_end) # GNOME
  end

  def test_delete
    assert_key_binding("\e[3~", :key_delete)
  end

  def test_up_arrow
    assert_key_binding("\e[A", :ed_prev_history) # Console (80x25)
    assert_key_binding("\eGA", :ed_prev_history) # KDE
    assert_key_binding("\eOA", :ed_prev_history)
  end

  def test_down_arrow
    assert_key_binding("\e[B", :ed_next_history) # Console (80x25)
    assert_key_binding("\eGB", :ed_next_history) # KDE
    assert_key_binding("\eOB", :ed_next_history)
  end

  def test_right_arrow
    assert_key_binding("\e[C", :ed_next_char) # Console (80x25)
    assert_key_binding("\eGC", :ed_next_char) # KDE
    assert_key_binding("\eOC", :ed_next_char)
  end

  def test_left_arrow
    assert_key_binding("\e[D", :ed_prev_char) # Console (80x25)
    assert_key_binding("\eGD", :ed_prev_char) # KDE
    assert_key_binding("\eOD", :ed_prev_char)
  end

  # Ctrl+arrow and Meta+arrow; always mapped regardless of terminfo enabled or not
  def test_extended
    assert_key_binding("\e[1;5C", :em_next_word) # Ctrl+→
    assert_key_binding("\e[1;5D", :ed_prev_word) # Ctrl+←
    assert_key_binding("\e[1;3C", :em_next_word) # Meta+→
    assert_key_binding("\e[1;3D", :ed_prev_word) # Meta+←
    assert_key_binding("\e\e[C", :em_next_word) # Meta+→
    assert_key_binding("\e\e[D", :ed_prev_word) # Meta+←
  end

  # Shift-Tab; always mapped regardless of terminfo enabled or not
  def test_shift_tab
    assert_key_binding("\e[Z", :completion_journey_up, [:emacs, :vi_insert])
  end

  # A few emacs bindings that are always mapped regardless of terminfo enabled or not
  def test_more_emacs
    assert_key_binding("\e ", :em_set_mark, [:emacs])
    assert_key_binding("\C-x\C-x", :em_exchange_mark, [:emacs])
  end
end
