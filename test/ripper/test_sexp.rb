begin
  require 'ripper'
  require 'test/unit'
  ripper_test = true
  module TestRipper; end
rescue LoadError
end

class TestRipper::Sexp < Test::Unit::TestCase
  def test_compile_error
    assert_nil Ripper.sexp("/")
    assert_nil Ripper.sexp("-")
    assert_nil Ripper.sexp("+")
    assert_nil Ripper.sexp("*")
    assert_nil Ripper.sexp("end")
    assert_nil Ripper.sexp("end 1")
  end
end if ripper_test
