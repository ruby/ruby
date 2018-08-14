require 'test/unit'
require '-test-/scan_args'

class TestScanArgs < Test::Unit::TestCase
  def test_lead
    assert_raise(ArgumentError) {Bug::ScanArgs.lead()}
    assert_equal([1, "a"], Bug::ScanArgs.lead("a"))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead("a", "b")}
  end

  def test_opt
    assert_equal([0, nil], Bug::ScanArgs.opt())
    assert_equal([1, "a"], Bug::ScanArgs.opt("a"))
    assert_raise(ArgumentError) {Bug::ScanArgs.opt("a", "b")}
  end

  def test_lead_opt
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt()}
    assert_equal([1, "a", nil], Bug::ScanArgs.lead_opt("a"))
    assert_equal([2, "a", "b"], Bug::ScanArgs.lead_opt("a", "b"))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt("a", "b", "c")}
  end

  def test_var
    assert_equal([0, []], Bug::ScanArgs.var())
    assert_equal([3, ["a", "b", "c"]], Bug::ScanArgs.var("a", "b", "c"))
  end

  def test_lead_var
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var()}
    assert_equal([3, "a", ["b", "c"]], Bug::ScanArgs.lead_var("a", "b", "c"))
  end

  def test_opt_var
    assert_equal([0, nil, []], Bug::ScanArgs.opt_var())
    assert_equal([3, "a", ["b", "c"]], Bug::ScanArgs.opt_var("a", "b", "c"))
  end

  def test_lead_opt_var
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_var()}
    assert_equal([3, "a", "b", ["c"]], Bug::ScanArgs.lead_opt_var("a", "b", "c"))
  end

  def test_opt_trail
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_trail()}
    assert_equal([2, "a", "b"], Bug::ScanArgs.opt_trail("a", "b"))
    assert_equal([1, nil, "a"], Bug::ScanArgs.opt_trail("a"))
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_trail("a", "b", "c")}
  end

  def test_lead_opt_trail
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail()}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail("a")}
    assert_equal([2, "a", nil, "b"], Bug::ScanArgs.lead_opt_trail("a", "b"))
    assert_equal([3, "a", "b", "c"], Bug::ScanArgs.lead_opt_trail("a", "b", "c"))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail("a", "b", "c", "d")}
  end

  def test_var_trail
    assert_raise(ArgumentError) {Bug::ScanArgs.var_trail()}
    assert_equal([1, [], "a"], Bug::ScanArgs.var_trail("a"))
    assert_equal([2, ["a"], "b"], Bug::ScanArgs.var_trail("a", "b"))
  end

  def test_lead_var_trail
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var_trail("a")}
    assert_equal([2, "a", [], "b"], Bug::ScanArgs.lead_var_trail("a", "b"))
    assert_equal([3, "a", ["b"], "c"], Bug::ScanArgs.lead_var_trail("a", "b", "c"))
  end

  def test_opt_var_trail
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_var_trail()}
    assert_equal([1, nil, [], "a"], Bug::ScanArgs.opt_var_trail("a"))
    assert_equal([2, "a", [], "b"], Bug::ScanArgs.opt_var_trail("a", "b"))
    assert_equal([3, "a", ["b"], "c"], Bug::ScanArgs.opt_var_trail("a", "b", "c"))
  end

  def test_lead_opt_var_trail
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_var_trail("a")}
    assert_equal([2, "a", nil, [], "b"], Bug::ScanArgs.lead_opt_var_trail("a", "b"))
    assert_equal([3, "a", "b", [], "c"], Bug::ScanArgs.lead_opt_var_trail("a", "b", "c"))
    assert_equal([4, "a", "b", ["c"], "d"], Bug::ScanArgs.lead_opt_var_trail("a", "b", "c", "d"))
  end

  def test_hash
    assert_equal([0, nil], Bug::ScanArgs.hash())
    assert_raise(ArgumentError) {Bug::ScanArgs.hash("a")}
    assert_equal([0, {a: 0}], Bug::ScanArgs.hash(a: 0))
  end

  def test_lead_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_hash()}
    assert_equal([1, "a", nil], Bug::ScanArgs.lead_hash("a"))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_hash("a", "b")}
    assert_equal([1, "a", {b: 1}], Bug::ScanArgs.lead_hash("a", b: 1))
    assert_equal([1, {b: 1}, nil], Bug::ScanArgs.lead_hash(b: 1))
  end

  def test_opt_hash
    assert_equal([0, nil, nil], Bug::ScanArgs.opt_hash())
    assert_equal([1, "a", nil], Bug::ScanArgs.opt_hash("a"))
    assert_equal([0, nil, {b: 1}], Bug::ScanArgs.opt_hash(b: 1))
    assert_equal([1, "a", {b: 1}], Bug::ScanArgs.opt_hash("a", b: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_hash("a", "b")}
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_hash("a"=>0, b: 1)}
  end

  def test_lead_opt_hash
    assert_equal([1, "a", nil, nil], Bug::ScanArgs.lead_opt_hash("a"))
    assert_equal([2, "a", "b", nil], Bug::ScanArgs.lead_opt_hash("a", "b"))
    assert_equal([1, "a", nil, {c: 1}], Bug::ScanArgs.lead_opt_hash("a", c: 1))
    assert_equal([2, "a", "b", {c: 1}], Bug::ScanArgs.lead_opt_hash("a", "b", c: 1))
    assert_equal([1, {c: 1}, nil, nil], Bug::ScanArgs.lead_opt_hash(c: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_hash("a", "b", "c")}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_hash("a", "b"=>0, c: 1)}
  end

  def test_var_hash
    assert_equal([0, [], nil], Bug::ScanArgs.var_hash())
    assert_equal([1, ["a"], nil], Bug::ScanArgs.var_hash("a"))
    assert_equal([1, ["a"], {b: 1}], Bug::ScanArgs.var_hash("a", b: 1))
    assert_equal([0, [], {b: 1}], Bug::ScanArgs.var_hash(b: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.var_hash("a"=>0, b: 1)}
  end

  def test_lead_var_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var_hash()}
    assert_equal([1, "a", [], nil], Bug::ScanArgs.lead_var_hash("a"))
    assert_equal([2, "a", ["b"], nil], Bug::ScanArgs.lead_var_hash("a", "b"))
    assert_equal([2, "a", ["b"], {c: 1}], Bug::ScanArgs.lead_var_hash("a", "b", c: 1))
    assert_equal([1, "a", [], {c: 1}], Bug::ScanArgs.lead_var_hash("a", c: 1))
    assert_equal([1, {c: 1}, [], nil], Bug::ScanArgs.lead_var_hash(c: 1))
    assert_equal([3, "a", ["b", "c"], nil], Bug::ScanArgs.lead_var_hash("a", "b", "c"))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var_hash("a", "b"=>0, c: 1)}
  end

  def test_opt_var_hash
    assert_equal([0, nil, [], nil], Bug::ScanArgs.opt_var_hash())
    assert_equal([1, "a", [], nil], Bug::ScanArgs.opt_var_hash("a"))
    assert_equal([2, "a", ["b"], nil], Bug::ScanArgs.opt_var_hash("a", "b"))
    assert_equal([2, "a", ["b"], {c: 1}], Bug::ScanArgs.opt_var_hash("a", "b", c: 1))
    assert_equal([1, "a", [], {c: 1}], Bug::ScanArgs.opt_var_hash("a", c: 1))
    assert_equal([0, nil, [], {c: 1}], Bug::ScanArgs.opt_var_hash(c: 1))
    assert_equal([3, "a", ["b", "c"], nil], Bug::ScanArgs.opt_var_hash("a", "b", "c"))
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_var_hash("a", "b"=>0, c: 1)}
  end

  def test_lead_opt_var_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_var_hash()}
    assert_equal([1, "a", nil, [], nil], Bug::ScanArgs.lead_opt_var_hash("a"))
    assert_equal([2, "a", "b", [], nil], Bug::ScanArgs.lead_opt_var_hash("a", "b"))
    assert_equal([2, "a", "b", [], {c: 1}], Bug::ScanArgs.lead_opt_var_hash("a", "b", c: 1))
    assert_equal([1, "a", nil, [], {c: 1}], Bug::ScanArgs.lead_opt_var_hash("a", c: 1))
    assert_equal([1, {c: 1}, nil, [], nil], Bug::ScanArgs.lead_opt_var_hash(c: 1))
    assert_equal([3, "a", "b", ["c"], nil], Bug::ScanArgs.lead_opt_var_hash("a", "b", "c"))
    assert_equal([3, "a", "b", ["c"], {d: 1}], Bug::ScanArgs.lead_opt_var_hash("a", "b", "c", d: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_var_hash("a", "b", "c"=>0, d: 1)}
  end

  def test_opt_trail_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_trail_hash()}
    assert_equal([1, nil, "a", nil], Bug::ScanArgs.opt_trail_hash("a"))
    assert_equal([2, "a", "b", nil], Bug::ScanArgs.opt_trail_hash("a", "b"))
    assert_equal([1, nil, "a", {c: 1}], Bug::ScanArgs.opt_trail_hash("a", c: 1))
    assert_equal([2, "a", "b", {c: 1}], Bug::ScanArgs.opt_trail_hash("a", "b", c: 1))
    assert_equal([1, nil, {c: 1}, nil], Bug::ScanArgs.opt_trail_hash(c: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_trail_hash("a", "b", "c")}
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_trail_hash("a", "b"=>0, c: 1)}
  end

  def test_lead_opt_trail_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail_hash()}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail_hash("a")}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail_hash(c: 1)}
    assert_equal([2, "a", nil, "b", nil], Bug::ScanArgs.lead_opt_trail_hash("a", "b"))
    assert_equal([2, "a", nil, {c: 1}, nil], Bug::ScanArgs.lead_opt_trail_hash("a", c: 1))
    assert_equal([2, "a", nil, "b", {c: 1}], Bug::ScanArgs.lead_opt_trail_hash("a", "b", c: 1))
    assert_equal([3, "a", "b", "c", nil], Bug::ScanArgs.lead_opt_trail_hash("a", "b", "c"))
    assert_equal([3, "a", "b", "c", {c: 1}], Bug::ScanArgs.lead_opt_trail_hash("a", "b", "c", c: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail_hash("a", "b", "c", "d")}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_trail_hash("a", "b", "c"=>0, c: 1)}
  end

  def test_var_trail_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.var_trail_hash()}
    assert_equal([1, [], "a", nil], Bug::ScanArgs.var_trail_hash("a"))
    assert_equal([2, ["a"], "b", nil], Bug::ScanArgs.var_trail_hash("a", "b"))
    assert_equal([1, [], "a", {c: 1}], Bug::ScanArgs.var_trail_hash("a", c: 1))
    assert_equal([2, ["a"], "b", {c: 1}], Bug::ScanArgs.var_trail_hash("a", "b", c: 1))
    assert_equal([1, [], {c: 1}, nil], Bug::ScanArgs.var_trail_hash(c: 1))
    assert_equal([3, ["a", "b"], "c", nil], Bug::ScanArgs.var_trail_hash("a", "b", "c"))
    assert_equal([3, ["a", "b"], "c", {c: 1}], Bug::ScanArgs.var_trail_hash("a", "b", "c", c: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.var_trail_hash("a", "b", "c"=>0, c: 1)}
  end

  def test_lead_var_trail_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var_trail_hash()}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var_trail_hash("a")}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var_trail_hash(c: 1)}
    assert_equal([2, "a", [], {c: 1}, nil], Bug::ScanArgs.lead_var_trail_hash("a", c: 1))
    assert_equal([2, "a", [], "b", nil], Bug::ScanArgs.lead_var_trail_hash("a", "b"))
    assert_equal([2, "a", [], "b", {c: 1}], Bug::ScanArgs.lead_var_trail_hash("a", "b", c: 1))
    assert_equal([3, "a", ["b"], "c", nil], Bug::ScanArgs.lead_var_trail_hash("a", "b", "c"))
    assert_equal([3, "a", ["b"], "c", {c: 1}], Bug::ScanArgs.lead_var_trail_hash("a", "b", "c", c: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_var_trail_hash("a", "b", c: 1, "c"=>0)}
  end

  def test_opt_var_trail_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_var_trail_hash()}
    assert_equal([1, nil, [], "a", nil], Bug::ScanArgs.opt_var_trail_hash("a"))
    assert_equal([1, nil, [], {c: 1}, nil], Bug::ScanArgs.opt_var_trail_hash(c: 1))
    assert_equal([1, nil, [], "a", {c: 1}], Bug::ScanArgs.opt_var_trail_hash("a", c: 1))
    assert_equal([2, "a", [], "b", nil], Bug::ScanArgs.opt_var_trail_hash("a", "b"))
    assert_equal([2, "a", [], "b", {c: 1}], Bug::ScanArgs.opt_var_trail_hash("a", "b", c: 1))
    assert_equal([3, "a", ["b"], "c", nil], Bug::ScanArgs.opt_var_trail_hash("a", "b", "c"))
    assert_equal([3, "a", ["b"], "c", {c: 1}], Bug::ScanArgs.opt_var_trail_hash("a", "b", "c", c: 1))
    assert_raise(ArgumentError) {Bug::ScanArgs.opt_var_trail_hash("a", "b", "c"=>0, c: 1)}
  end

  def test_lead_opt_var_trail_hash
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_var_trail_hash()}
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_var_trail_hash("a")}
    assert_equal([2, "a", nil, [], {b: 1}, nil], Bug::ScanArgs.lead_opt_var_trail_hash("a", b: 1))
    assert_equal([2, "a", nil, [], "b", nil], Bug::ScanArgs.lead_opt_var_trail_hash("a", "b"))
    assert_equal([2, "a", nil, [], "b", {c: 1}], Bug::ScanArgs.lead_opt_var_trail_hash("a", "b", c: 1))
    assert_equal([3, "a", "b", [], "c", nil], Bug::ScanArgs.lead_opt_var_trail_hash("a", "b", "c"))
    assert_equal([3, "a", "b", [], "c", {c: 1}], Bug::ScanArgs.lead_opt_var_trail_hash("a", "b", "c", c: 1))
    assert_equal([4, "a", "b", ["c"], "d", nil], Bug::ScanArgs.lead_opt_var_trail_hash("a", "b", "c", "d"))
    assert_raise(ArgumentError) {Bug::ScanArgs.lead_opt_var_trail_hash("a", "b", "c", "d"=>0, c: 1)}
  end
end
