# frozen_string_literal: true

require 'test/unit'

class TestWarning < Test::Unit::TestCase
  def test_warn_called_only_when_category_enabled
    # Assert that warn is called when the category is enabled
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        Warning[:deprecated] = true
        $warnings = []
        def Warning.warn(msg, category:)
          $warnings << [msg, category]
        end
        assert_equal(0, $warnings.length)
        "" << 12
        assert_equal(1, $warnings.length)
      end;

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        Warning[:deprecated] = false
        $warnings = []
        def Warning.warn(msg, category:)
          $warnings << [msg, category]
        end
        assert_equal(0, $warnings.length)
        "" << 12
        assert_equal(0, $warnings.length, $warnings.join)
      end;
  end
end
