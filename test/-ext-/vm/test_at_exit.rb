# frozen_string_literal: false
class TestVM < Test::Unit::TestCase

  # [Bug #12095]
  def test_at_exit

    assert_in_out_err([], <<-"end;", %w[begin end]) # do
      require '-test-/vm/at_exit'
      Bug::VM.register_at_exit(false)
      1000.times do
        Bug::VM.register_at_exit(nil)
        ["x"]*1000
      end
      GC.start
      Bug::VM.register_at_exit(true)
    end;
  end
end

