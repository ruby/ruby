require_relative 'helper'
require 'reline/ansi'

class Reline::ANSI::TestWithTerminfo < Reline::TestCase
  def setup
    Reline.send(:test_mode, ansi: true)
    @config = Reline::Config.new
    Reline::IOGate.set_default_key_bindings(@config, allow_terminfo: true)
  end

  def teardown
    Reline.send(:test_mode, ansi: false) # Change IOGate back to GeneralIO
    Reline.test_reset
  end

  # Home key
  def test_khome
    assert_key_binding(Reline::Terminfo.tigetstr('khome'), :ed_move_to_beg)
  rescue Reline::Terminfo::TerminfoError => e
    omit e.message
  end

  # End key
  def test_kend
    assert_key_binding(Reline::Terminfo.tigetstr('kend'), :ed_move_to_end)
  rescue Reline::Terminfo::TerminfoError => e
    omit e.message
  end

  # Delete key
  def test_kdch1
    assert_key_binding(Reline::Terminfo.tigetstr('kdch1'), :key_delete)
  rescue Reline::Terminfo::TerminfoError => e
    omit e.message
  end

  # Up arrow key
  def test_kcuu1
    assert_key_binding(Reline::Terminfo.tigetstr('kcuu1'), :ed_prev_history)
  rescue Reline::Terminfo::TerminfoError => e
    omit e.message
  end

  # Down arrow key
  def test_kcud1
    assert_key_binding(Reline::Terminfo.tigetstr('kcud1'), :ed_next_history)
  rescue Reline::Terminfo::TerminfoError => e
    omit e.message
  end

  # Right arrow key
  def test_kcuf1
    assert_key_binding(Reline::Terminfo.tigetstr('kcuf1'), :ed_next_char)
  rescue Reline::Terminfo::TerminfoError => e
    omit e.message
  end

  # Left arrow key
  def test_kcub1
    assert_key_binding(Reline::Terminfo.tigetstr('kcub1'), :ed_prev_char)
  rescue Reline::Terminfo::TerminfoError => e
    omit e.message
  end

  # Ctrl+arrow and Meta+arrow; always mapped regardless of terminfo enabled or not
  def test_extended
    assert_key_binding("\e[1;5C", :em_next_word) # Ctrl+→
    assert_key_binding("\e[1;5D", :ed_prev_word) # Ctrl+←
    assert_key_binding("\e[1;3C", :em_next_word) # Meta+→
    assert_key_binding("\e[1;3D", :ed_prev_word) # Meta+←
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
end if Reline::Terminfo.enabled?
