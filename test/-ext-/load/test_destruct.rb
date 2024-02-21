require "test/unit"

class TestDestruct < Test::Unit::TestCase
  def test_destruct_func_not_called
    assert_in_out_err(["-r-test-/load/destruct"], "", [])
  end

  def test_destruct_func_called_when_free_on_exit
    assert_in_out_err([{"RUBY_FREE_AT_EXIT" => "1"}, "-W0", "-r-test-/load/destruct"], "puts 'Running Ruby'", ["Running Ruby", "Calling Destruct_destruct"])
  end
end
