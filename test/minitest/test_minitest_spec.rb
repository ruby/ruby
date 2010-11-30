############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

require 'minitest/spec'

MiniTest::Unit.autorun

describe MiniTest::Spec do
  before do
    @assertion_count = 4
  end

  after do
    self._assertions.must_equal @assertion_count
  end

  # TODO: figure out how the hell to write a test for this
  # it "will skip if there is no block"

  it "needs to have all methods named well" do
    @assertion_count = 2

    methods = Object.public_instance_methods.find_all { |n| n =~ /^must|^wont/ }
    methods.map! { |m| m.to_s } if Symbol === methods.first

    musts, wonts = methods.sort.partition { |m| m =~ /^must/ }

    expected_musts = %w(must_be
                        must_be_close_to
                        must_be_empty
                        must_be_instance_of
                        must_be_kind_of
                        must_be_nil
                        must_be_same_as
                        must_be_silent
                        must_be_within_delta
                        must_be_within_epsilon
                        must_equal
                        must_include
                        must_match
                        must_output
                        must_raise
                        must_respond_to
                        must_send
                        must_throw)

    bad = %w[not raise throw send output be_silent]

    expected_wonts = expected_musts.map { |m| m.sub(/^must/, 'wont') }
    expected_wonts.reject! { |m| m =~ /wont_#{Regexp.union(*bad)}/ }

    musts.must_equal expected_musts
    wonts.must_equal expected_wonts
  end

  it "needs to verify equality" do
    (6 * 7).must_equal(42).must_equal true
    proc { (6 * 9).must_equal(42) }.must_raise MiniTest::Assertion
  end

  it "needs to verify floats within a delta" do
    (6.0 * 7).must_be_close_to(42.0).must_equal true
    proc { 42.002.must_be_close_to 42.0 }.must_raise MiniTest::Assertion
  end

  it "needs to verify types of objects" do
    (6 * 7).must_be_instance_of(Fixnum).must_equal true
    proc { (6 * 7).must_be_instance_of String }.must_raise MiniTest::Assertion
  end

  it "needs to verify kinds of objects" do
    @assertion_count = 6

    (6 * 7).must_be_kind_of(Fixnum).must_equal true
    (6 * 7).must_be_kind_of(Numeric).must_equal true
    proc { (6 * 7).must_be_kind_of String }.must_raise MiniTest::Assertion
  end

  it "needs to verify regexp matches" do
    @assertion_count = 6

    "blah".must_match(/\w+/).must_equal true
    proc { "blah".must_match(/\d+/) }.must_raise MiniTest::Assertion
  end

  it "needs to verify nil" do
    nil.must_be_nil.must_equal true
    proc { 42.must_be_nil }.must_raise MiniTest::Assertion
  end

  it "needs to verify using any operator" do
    41.must_be(:<, 42).must_equal true
    proc { 42.must_be(:<, 41) }.must_raise MiniTest::Assertion
  end

  it "needs to catch an expected exception" do
    @assertion_count = 2

    proc { raise "blah" }.must_raise RuntimeError
    proc { raise MiniTest::Assertion }.must_raise MiniTest::Assertion
  end

  it "needs to catch an unexpected exception" do
    @assertion_count = 2

    proc {
      proc { raise MiniTest::Assertion }.must_raise(RuntimeError)
    }.must_raise MiniTest::Assertion
  end

  it "needs raise if an expected exception is not raised" do
    @assertion_count = 2

    proc { proc { 42 }.must_raise(RuntimeError) }.must_raise MiniTest::Assertion
  end

  it "needs to be able to catch a MiniTest::Assertion exception" do
    @assertion_count = 2

    proc { 1.wont_equal 1 }.must_raise MiniTest::Assertion
  end

  it "needs to verify using respond_to" do
    42.must_respond_to(:+).must_equal true
    proc { 42.must_respond_to(:clear) }.must_raise MiniTest::Assertion
  end

  it "needs to verify identity" do
    1.must_be_same_as(1).must_equal true
    proc { 1.must_be_same_as 2 }.must_raise MiniTest::Assertion
  end

  it "needs to verify throw" do
    @assertion_count = 6

    proc { throw :blah }.must_throw(:blah).must_equal true
    proc { proc { }.must_throw(:blah) }.must_raise MiniTest::Assertion
    proc { proc { throw :xxx }.must_throw(:blah) }.must_raise MiniTest::Assertion
  end

  it "needs to verify inequality" do
    42.wont_equal(6 * 9).must_equal false
    proc { 1.wont_equal 1 }.must_raise MiniTest::Assertion
  end

  it "needs to verify mismatch" do
    @assertion_count = 6
    "blah".wont_match(/\d+/).must_equal false
    proc { "blah".wont_match(/\w+/) }.must_raise MiniTest::Assertion
  end

  it "needs to verify non-nil" do
    42.wont_be_nil.must_equal false
    proc { nil.wont_be_nil }.must_raise MiniTest::Assertion
  end

  it "needs to verify non-identity" do
    1.wont_be_same_as(2).must_equal false
    proc { 1.wont_be_same_as 1 }.must_raise MiniTest::Assertion
  end

  it "needs to verify output in stdout" do
    proc { print "blah" }.must_output("blah").must_equal true

    proc {
      proc { print "xxx" }.must_output("blah")
    }.must_raise MiniTest::Assertion
  end

  it "needs to verify output in stderr" do
    proc { $stderr.print "blah" }.must_output(nil, "blah").must_equal true

    proc {
      proc { $stderr.print "xxx" }.must_output(nil, "blah")
    }.must_raise MiniTest::Assertion
  end

  it "needs to ensure silence" do
    @assertion_count = 5

    proc {  }.must_be_silent.must_equal true

    proc {
      proc { print "xxx" }.must_be_silent
    }.must_raise MiniTest::Assertion
  end

  it "needs to be sensible about must_include order" do
    @assertion_count = 6
    [1, 2, 3].must_include(2).must_equal true
    proc { [1, 2, 3].must_include 5 }.must_raise MiniTest::Assertion
  end

  it "needs to be sensible about wont_include order" do
    @assertion_count = 6
    [1, 2, 3].wont_include(5).must_equal false
    proc { [1, 2, 3].wont_include 2 }.must_raise MiniTest::Assertion
  end
end

class TestMeta < MiniTest::Unit::TestCase
  def test_structure
    x = y = z = nil
    x = describe "top-level thingy" do
      before {}
      after  {}

      it "top-level-it" do end

      y = describe "inner thingy" do
        before {}
        it "inner-it" do end

        z = describe "very inner thingy" do
          before {}
          it "inner-it" do end
        end
      end
    end

    assert_equal "top-level thingy", x.to_s
    assert_equal "top-level thingy::inner thingy", y.to_s
    assert_equal "top-level thingy::inner thingy::very inner thingy", z.to_s

    top_methods = %w(setup teardown test_0001_top_level_it)
    inner_methods = %w(setup test_0001_inner_it)

    assert_equal top_methods,   x.instance_methods(false).sort.map {|o| o.to_s }
    assert_equal inner_methods, y.instance_methods(false).sort.map {|o| o.to_s }
    assert_equal inner_methods, z.instance_methods(false).sort.map {|o| o.to_s }
  end
end
