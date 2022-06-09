# frozen_string_literal: true
require_relative '../../../lib/test/unit'

class TestHung < Test::Unit::TestCase
  def test_success_at_worker
    assert true
  end

  def test_hungup_at_worker
    if on_parallel_worker?
      sleep 10
    end
    assert true
  end
end
