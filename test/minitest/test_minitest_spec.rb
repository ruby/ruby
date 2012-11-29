# encoding: utf-8
######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

# encoding: utf-8
require 'minitest/autorun'
require 'stringio'

class MiniSpecA < MiniTest::Spec; end
class MiniSpecB < MiniTest::Spec; end
class ExampleA; end
class ExampleB < ExampleA; end

describe MiniTest::Spec do
  # do not parallelize this suite... it just can't handle it.

  def assert_triggered expected = "blah", klass = MiniTest::Assertion
    @assertion_count += 2

    e = assert_raises(klass) do
      yield
    end

    msg = e.message.sub(/(---Backtrace---).*/m, '\1')
    msg.gsub!(/\(oid=[-0-9]+\)/, '(oid=N)')

    assert_equal expected, msg
  end

  before do
    @assertion_count = 4
  end

  after do
    self._assertions.must_equal @assertion_count
  end

  it "needs to be able to catch a MiniTest::Assertion exception" do
    @assertion_count = 1

    assert_triggered "Expected 1 to not be equal to 1." do
      1.wont_equal 1
    end
  end

  it "needs to be sensible about must_include order" do
    @assertion_count += 3 # must_include is 2 assertions

    [1, 2, 3].must_include(2).must_equal true

    assert_triggered "Expected [1, 2, 3] to include 5." do
      [1, 2, 3].must_include 5
    end

    assert_triggered "msg.\nExpected [1, 2, 3] to include 5." do
      [1, 2, 3].must_include 5, "msg"
    end
  end

  it "needs to be sensible about wont_include order" do
    @assertion_count += 3 # wont_include is 2 assertions

    [1, 2, 3].wont_include(5).must_equal false

    assert_triggered "Expected [1, 2, 3] to not include 2." do
      [1, 2, 3].wont_include 2
    end

    assert_triggered "msg.\nExpected [1, 2, 3] to not include 2." do
      [1, 2, 3].wont_include 2, "msg"
    end
  end

  it "needs to catch an expected exception" do
    @assertion_count = 2

    proc { raise "blah" }.must_raise RuntimeError
    proc { raise MiniTest::Assertion }.must_raise MiniTest::Assertion
  end

  it "needs to catch an unexpected exception" do
    @assertion_count -= 2 # no positive

    msg = <<-EOM.gsub(/^ {6}/, '').chomp
      [RuntimeError] exception expected, not
      Class: <MiniTest::Assertion>
      Message: <\"MiniTest::Assertion\">
      ---Backtrace---
    EOM

    assert_triggered msg do
      proc { raise MiniTest::Assertion }.must_raise RuntimeError
    end

    assert_triggered "msg.\n#{msg}" do
      proc { raise MiniTest::Assertion }.must_raise RuntimeError, "msg"
    end
  end

  it "needs to ensure silence" do
    @assertion_count -= 1 # no msg
    @assertion_count += 2 # assert_output is 2 assertions

    proc {  }.must_be_silent.must_equal true

    assert_triggered "In stdout.\nExpected: \"\"\n  Actual: \"xxx\"" do
      proc { print "xxx" }.must_be_silent
    end
  end

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

  it "needs to raise if an expected exception is not raised" do
    @assertion_count -= 2 # no positive test

    assert_triggered "RuntimeError expected but nothing was raised." do
      proc { 42 }.must_raise RuntimeError
    end

    assert_triggered "msg.\nRuntimeError expected but nothing was raised." do
      proc { 42 }.must_raise RuntimeError, "msg"
    end
  end

  it "needs to verify binary messages" do
    42.wont_be(:<, 24).must_equal false

    assert_triggered 'Expected 24 to not be < 42.' do
      24.wont_be :<, 42
    end

    assert_triggered "msg.\nExpected 24 to not be < 42." do
      24.wont_be :<, 42, "msg"
    end
  end

  it "needs to verify emptyness" do
    @assertion_count += 3 # empty is 2 assertions

    [].must_be_empty.must_equal true

    assert_triggered "Expected [42] to be empty." do
      [42].must_be_empty
    end

    assert_triggered "msg.\nExpected [42] to be empty." do
      [42].must_be_empty "msg"
    end
  end

  it "needs to verify equality" do
    (6 * 7).must_equal(42).must_equal true

    assert_triggered "Expected: 42\n  Actual: 54" do
      (6 * 9).must_equal 42
    end

    assert_triggered "msg.\nExpected: 42\n  Actual: 54" do
      (6 * 9).must_equal 42, "msg"
    end
  end

  it "needs to verify floats outside a delta" do
    @assertion_count += 1 # extra test

    24.wont_be_close_to(42).must_equal false

    assert_triggered 'Expected |42 - 42.0| (0.0) to not be < 0.001.' do
      (6 * 7.0).wont_be_close_to 42
    end

    assert_triggered 'Expected |42 - 42.0| (0.0) to not be < 1.0e-05.' do
      (6 * 7.0).wont_be_close_to 42, 0.00001
    end

    assert_triggered "msg.\nExpected |42 - 42.0| (0.0) to not be < 1.0e-05." do
      (6 * 7.0).wont_be_close_to 42, 0.00001, "msg"
    end
  end

  it "needs to verify floats outside an epsilon" do
    @assertion_count += 1 # extra test

    24.wont_be_within_epsilon(42).must_equal false

    assert_triggered 'Expected |42 - 42.0| (0.0) to not be < 0.042.' do
      (6 * 7.0).wont_be_within_epsilon 42
    end

    assert_triggered 'Expected |42 - 42.0| (0.0) to not be < 0.00042.' do
      (6 * 7.0).wont_be_within_epsilon 42, 0.00001
    end

    assert_triggered "msg.\nExpected |42 - 42.0| (0.0) to not be < 0.00042." do
      (6 * 7.0).wont_be_within_epsilon 42, 0.00001, "msg"
    end
  end

  it "needs to verify floats within a delta" do
    @assertion_count += 1 # extra test

    (6.0 * 7).must_be_close_to(42.0).must_equal true

    assert_triggered 'Expected |0.0 - 0.01| (0.01) to be < 0.001.' do
      (1.0 / 100).must_be_close_to 0.0
    end

    assert_triggered 'Expected |0.0 - 0.001| (0.001) to be < 1.0e-06.' do
      (1.0 / 1000).must_be_close_to 0.0, 0.000001
    end

    assert_triggered "msg.\nExpected |0.0 - 0.001| (0.001) to be < 1.0e-06." do
      (1.0 / 1000).must_be_close_to 0.0, 0.000001, "msg"
    end
  end

  it "needs to verify floats within an epsilon" do
    @assertion_count += 1 # extra test

    (6.0 * 7).must_be_within_epsilon(42.0).must_equal true

    assert_triggered 'Expected |0.0 - 0.01| (0.01) to be < 0.0.' do
      (1.0 / 100).must_be_within_epsilon 0.0
    end

    assert_triggered 'Expected |0.0 - 0.001| (0.001) to be < 0.0.' do
      (1.0 / 1000).must_be_within_epsilon 0.0, 0.000001
    end

    assert_triggered "msg.\nExpected |0.0 - 0.001| (0.001) to be < 0.0." do
      (1.0 / 1000).must_be_within_epsilon 0.0, 0.000001, "msg"
    end
  end

  it "needs to verify identity" do
    1.must_be_same_as(1).must_equal true

    assert_triggered "Expected 1 (oid=N) to be the same as 2 (oid=N)." do
      1.must_be_same_as 2
    end

    assert_triggered "msg.\nExpected 1 (oid=N) to be the same as 2 (oid=N)." do
      1.must_be_same_as 2, "msg"
    end
  end

  it "needs to verify inequality" do
    42.wont_equal(6 * 9).must_equal false

    assert_triggered "Expected 1 to not be equal to 1." do
      1.wont_equal 1
    end

    assert_triggered "msg.\nExpected 1 to not be equal to 1." do
      1.wont_equal 1, "msg"
    end
  end

  it "needs to verify instances of a class" do
    42.wont_be_instance_of(String).must_equal false

    assert_triggered 'Expected 42 to not be an instance of Fixnum.' do
      42.wont_be_instance_of Fixnum
    end

    assert_triggered "msg.\nExpected 42 to not be an instance of Fixnum." do
      42.wont_be_instance_of Fixnum, "msg"
    end
  end

  it "needs to verify kinds of a class" do
    42.wont_be_kind_of(String).must_equal false

    assert_triggered 'Expected 42 to not be a kind of Integer.' do
      42.wont_be_kind_of Integer
    end

    assert_triggered "msg.\nExpected 42 to not be a kind of Integer." do
      42.wont_be_kind_of Integer, "msg"
    end
  end

  it "needs to verify kinds of objects" do
    @assertion_count += 2 # extra test

    (6 * 7).must_be_kind_of(Fixnum).must_equal true
    (6 * 7).must_be_kind_of(Numeric).must_equal true

    assert_triggered "Expected 42 to be a kind of String, not Fixnum." do
      (6 * 7).must_be_kind_of String
    end

    assert_triggered "msg.\nExpected 42 to be a kind of String, not Fixnum." do
      (6 * 7).must_be_kind_of String, "msg"
    end
  end

  it "needs to verify mismatch" do
    @assertion_count += 3 # match is 2

    "blah".wont_match(/\d+/).must_equal false

    assert_triggered "Expected /\\w+/ to not match \"blah\"." do
      "blah".wont_match(/\w+/)
    end

    assert_triggered "msg.\nExpected /\\w+/ to not match \"blah\"." do
      "blah".wont_match(/\w+/, "msg")
    end
  end

  it "needs to verify nil" do
    nil.must_be_nil.must_equal true

    assert_triggered "Expected 42 to be nil." do
      42.must_be_nil
    end

    assert_triggered "msg.\nExpected 42 to be nil." do
      42.must_be_nil "msg"
    end
  end

  it "needs to verify non-emptyness" do
    @assertion_count += 3 # empty is 2 assertions

    ['some item'].wont_be_empty.must_equal false

    assert_triggered "Expected [] to not be empty." do
      [].wont_be_empty
    end

    assert_triggered "msg.\nExpected [] to not be empty." do
      [].wont_be_empty "msg"
    end
  end

  it "needs to verify non-identity" do
    1.wont_be_same_as(2).must_equal false

    assert_triggered "Expected 1 (oid=N) to not be the same as 1 (oid=N)." do
      1.wont_be_same_as 1
    end

    assert_triggered "msg.\nExpected 1 (oid=N) to not be the same as 1 (oid=N)." do
      1.wont_be_same_as 1, "msg"
    end
  end

  it "needs to verify non-nil" do
    42.wont_be_nil.must_equal false

    assert_triggered "Expected nil to not be nil." do
      nil.wont_be_nil
    end

    assert_triggered "msg.\nExpected nil to not be nil." do
      nil.wont_be_nil "msg"
    end
  end

  it "needs to verify objects not responding to a message" do
    "".wont_respond_to(:woot!).must_equal false

    assert_triggered 'Expected "" to not respond to to_s.' do
      "".wont_respond_to :to_s
    end

    assert_triggered "msg.\nExpected \"\" to not respond to to_s." do
      "".wont_respond_to :to_s, "msg"
    end
  end

  it "needs to verify output in stderr" do
    @assertion_count -= 1 # no msg

    proc { $stderr.print "blah" }.must_output(nil, "blah").must_equal true

    assert_triggered "In stderr.\nExpected: \"blah\"\n  Actual: \"xxx\"" do
      proc { $stderr.print "xxx" }.must_output(nil, "blah")
    end
  end

  it "needs to verify output in stdout" do
    @assertion_count -= 1 # no msg

    proc { print "blah" }.must_output("blah").must_equal true

    assert_triggered "In stdout.\nExpected: \"blah\"\n  Actual: \"xxx\"" do
      proc { print "xxx" }.must_output("blah")
    end
  end

  it "needs to verify regexp matches" do
    @assertion_count += 3 # must_match is 2 assertions

    "blah".must_match(/\w+/).must_equal true

    assert_triggered "Expected /\\d+/ to match \"blah\"." do
      "blah".must_match(/\d+/)
    end

    assert_triggered "msg.\nExpected /\\d+/ to match \"blah\"." do
      "blah".must_match(/\d+/, "msg")
    end
  end

  it "needs to verify throw" do
    @assertion_count += 2 # 2 extra tests

    proc { throw :blah }.must_throw(:blah).must_equal true

    assert_triggered "Expected :blah to have been thrown." do
      proc { }.must_throw :blah
    end

    assert_triggered "Expected :blah to have been thrown, not :xxx." do
      proc { throw :xxx }.must_throw :blah
    end

    assert_triggered "msg.\nExpected :blah to have been thrown." do
      proc { }.must_throw :blah, "msg"
    end

    assert_triggered "msg.\nExpected :blah to have been thrown, not :xxx." do
      proc { throw :xxx }.must_throw :blah, "msg"
    end
  end

  it "needs to verify types of objects" do
    (6 * 7).must_be_instance_of(Fixnum).must_equal true

    exp = "Expected 42 to be an instance of String, not Fixnum."

    assert_triggered exp do
      (6 * 7).must_be_instance_of String
    end

    assert_triggered "msg.\n#{exp}" do
      (6 * 7).must_be_instance_of String, "msg"
    end
  end

  it "needs to verify using any (negative) predicate" do
    @assertion_count -= 1 # doesn't take a message

    "blah".wont_be(:empty?).must_equal false

    assert_triggered "Expected \"\" to not be empty?." do
      "".wont_be :empty?
    end
  end

  it "needs to verify using any binary operator" do
    @assertion_count -= 1 # no msg

    41.must_be(:<, 42).must_equal true

    assert_triggered "Expected 42 to be < 41." do
      42.must_be(:<, 41)
    end
  end

  it "needs to verify using any predicate" do
    @assertion_count -= 1 # no msg

    "".must_be(:empty?).must_equal true

    assert_triggered "Expected \"blah\" to be empty?." do
      "blah".must_be :empty?
    end
  end

  it "needs to verify using respond_to" do
    42.must_respond_to(:+).must_equal true

    assert_triggered "Expected 42 (Fixnum) to respond to #clear." do
      42.must_respond_to :clear
    end

    assert_triggered "msg.\nExpected 42 (Fixnum) to respond to #clear." do
      42.must_respond_to :clear, "msg"
    end
  end

end

describe MiniTest::Spec, :let do
  i_suck_and_my_tests_are_order_dependent!

  def _count
    $let_count ||= 0
  end

  let :count do
    $let_count += 1
    $let_count
  end

  it "is evaluated once per example" do
    _count.must_equal 0

    count.must_equal 1
    count.must_equal 1

    _count.must_equal 1
  end

  it "is REALLY evaluated once per example" do
    _count.must_equal 1

    count.must_equal 2
    count.must_equal 2

    _count.must_equal 2
  end
end

describe MiniTest::Spec, :subject do
  attr_reader :subject_evaluation_count

  subject do
    @subject_evaluation_count ||= 0
    @subject_evaluation_count  += 1
    @subject_evaluation_count
  end

  it "is evaluated once per example" do
    subject.must_equal 1
    subject.must_equal 1
    subject_evaluation_count.must_equal 1
  end
end

class TestMetaStatic < MiniTest::Unit::TestCase
  def test_children
    MiniTest::Spec.children.clear # prevents parallel run

    x = y = z = nil
    x = describe "top-level thingy" do
      y = describe "first thingy" do end

      it "top-level-it" do end

      z = describe "second thingy" do end
    end

    assert_equal [x], MiniTest::Spec.children
    assert_equal [y, z], x.children
    assert_equal [], y.children
    assert_equal [], z.children
  end
end

class TestMeta < MiniTest::Unit::TestCase
  parallelize_me! if ENV["PARALLEL"]

  def util_structure
    x = y = z = nil
    before_list = []
    after_list  = []
    x = describe "top-level thingy" do
      before { before_list << 1 }
      after  { after_list  << 1 }

      it "top-level-it" do end

      y = describe "inner thingy" do
        before { before_list << 2 }
        after  { after_list  << 2 }
        it "inner-it" do end

        z = describe "very inner thingy" do
          before { before_list << 3 }
          after  { after_list  << 3 }
          it "inner-it" do end

          it      {} # ignore me
          specify {} # anonymous it
        end
      end
    end

    return x, y, z, before_list, after_list
  end

  def test_register_spec_type
    original_types = MiniTest::Spec::TYPES.dup

    assert_equal [[//, MiniTest::Spec]], MiniTest::Spec::TYPES

    MiniTest::Spec.register_spec_type(/woot/, TestMeta)

    p = lambda do |x| true end
    MiniTest::Spec.register_spec_type TestMeta, &p

    keys = MiniTest::Spec::TYPES.map(&:first)

    assert_includes keys, /woot/
    assert_includes keys, p
  ensure
    MiniTest::Spec::TYPES.replace original_types
  end

  def test_spec_type
    original_types = MiniTest::Spec::TYPES.dup

    MiniTest::Spec.register_spec_type(/A$/, MiniSpecA)
    MiniTest::Spec.register_spec_type MiniSpecB do |desc|
      desc.superclass == ExampleA
    end

    assert_equal MiniSpecA, MiniTest::Spec.spec_type(ExampleA)
    assert_equal MiniSpecB, MiniTest::Spec.spec_type(ExampleB)
  ensure
    MiniTest::Spec::TYPES.replace original_types
  end

  def test_structure
    x, y, z, * = util_structure

    assert_equal "top-level thingy",                                  x.to_s
    assert_equal "top-level thingy::inner thingy",                    y.to_s
    assert_equal "top-level thingy::inner thingy::very inner thingy", z.to_s

    assert_equal "top-level thingy",  x.desc
    assert_equal "inner thingy",      y.desc
    assert_equal "very inner thingy", z.desc

    top_methods = %w(setup teardown test_0001_top-level-it)
    inner_methods1 = %w(setup teardown test_0001_inner-it)
    inner_methods2 = inner_methods1 +
      %w(test_0002_anonymous test_0003_anonymous)

    assert_equal top_methods,    x.instance_methods(false).sort.map(&:to_s)
    assert_equal inner_methods1, y.instance_methods(false).sort.map(&:to_s)
    assert_equal inner_methods2, z.instance_methods(false).sort.map(&:to_s)
  end

  def test_setup_teardown_behavior
    _, _, z, before_list, after_list = util_structure

    @tu = MiniTest::Unit.new
    MiniTest::Unit.runner = nil # protect the outer runner from the inner tests

    with_output do
      tc = z.new :test_0002_anonymous
      tc.run @tu
    end

    assert_equal [1, 2, 3], before_list
    assert_equal [3, 2, 1], after_list
  end

  def test_describe_first_structure
    x = x1 = x2 = y = z = nil
    x = describe "top-level thingy" do
      y = describe "first thingy" do end

      x1 = it "top level it" do end
      x2 = it "не латинские буквы-и-спецсимволы&いった α, β, γ, δ, ε hello!!! world" do end

      z = describe "second thingy" do end
    end

    test_methods = ['test_0001_top level it', 'test_0002_не латинские буквы-и-спецсимволы&いった α, β, γ, δ, ε hello!!! world'].sort

    assert_equal test_methods, [x1, x2]
    assert_equal test_methods,
      x.instance_methods.grep(/^test/).map {|o| o.to_s}.sort
    assert_equal [], y.instance_methods.grep(/^test/)
    assert_equal [], z.instance_methods.grep(/^test/)
  end

  def test_structure_subclasses
    z = nil
    x = Class.new MiniTest::Spec do
      def xyz; end
    end
    y = Class.new x do
      z = describe("inner") {}
    end

    assert_respond_to x.new(nil), "xyz"
    assert_respond_to y.new(nil), "xyz"
    assert_respond_to z.new(nil), "xyz"
  end

  def with_output # REFACTOR: dupe from metametameta
    synchronize do
      begin
        @output = StringIO.new("")
        MiniTest::Unit.output = @output

        yield
      ensure
        MiniTest::Unit.output = STDOUT
      end
    end
  end
end
