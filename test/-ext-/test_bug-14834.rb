# frozen_string_literal: true

class Test_BUG_14834 < Test::Unit::TestCase
  def test
    assert_ruby_status [], <<~'end;', '[ruby-core:87449] [Bug #14834]'
      require '-test-/bug_14834'
      Bug.bug_14834 do
        [123].group_by {}
      end
    end;
  end
end
