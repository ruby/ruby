require 'rubyunit'
require 'runit/cui/testrunner'
require 'rbconfig'
require 'drb/drb'
require 'drb/extservm'
require 'timeout'

class TestService
  @@scripts = %w(ut_drb.rb ut_array.rb ut_port.rb ut_large.rb ut_safe1.rb ut_eval.rb)

  def initialize(uri=nil, config={})
    ruby = Config::CONFIG["RUBY_INSTALL_NAME"]
    @manager = DRb::ExtServManager.new
    @@scripts.each do |nm|
      DRb::ExtServManager.command[nm] = "#{ruby} #{nm}"
    end
    @server = DRb::DRbServer.new(uri, @manager, config)
  end
  attr_reader :manager, :server
end

class Onecky
  include DRbUndumped
  def initialize(n)
    @num = n
  end

  def to_i
    @num.to_i
  end

  def sleep(n)
    Kernel.sleep(n)
    to_i
  end
end

class FailOnecky < Onecky
  class OneckyError < RuntimeError; end
  def to_i
    raise(OneckyError, @num.to_s)
  end
end

class XArray < Array
  def initialize(ary)
    ary.each do |x|
      self.push(x)
    end
  end
end

class DRbCoreTest < RUNIT::TestCase
  def setup
    @ext = $manager.service('ut_drb.rb')
    @there = @ext.front
  end

  def teardown
    @ext.stop_service
  end

  def test_00_DRbObject
    ro = DRbObject.new(nil, 'druby://localhost:12345')
    assert_equal('druby://localhost:12345', ro.__drburi)
    assert_equal(nil, ro.__drbref)
    
    ro = DRbObject.new_with_uri('druby://localhost:12345')
    assert_equal('druby://localhost:12345', ro.__drburi)
    assert_equal(nil, ro.__drbref)
    
    ro = DRbObject.new_with_uri('druby://localhost:12345?foobar')
    assert_equal('druby://localhost:12345', ro.__drburi)
    assert_equal(DRb::DRbURIOption.new('foobar'), ro.__drbref)
  end

  def test_01
    assert_equal("hello", @there.hello)
    onecky = Onecky.new('3')
    assert_equal(6, @there.sample(onecky, 1, 2))
    ary = @there.to_a
    assert_kind_of(DRb::DRbObject, ary)
  end

  def test_01_02_loop
    onecky = Onecky.new('3')
    50.times do 
      assert_equal(6, @there.sample(onecky, 1, 2))
      ary = @there.to_a
      assert_kind_of(DRb::DRbObject, ary)
    end
  end

  def test_02_unknown
    obj = @there.unknown_class
    assert_kind_of(DRb::DRbUnknown, obj)
    assert_equal('Unknown2', obj.name)

    obj = @there.unknown_module
    assert_kind_of(DRb::DRbUnknown, obj)
    if RUBY_VERSION >= '1.8'
      assert_equal('DRbEx::', obj.name)
    else
      assert_equal('DRbEx', obj.name)
    end

    assert_exception(DRb::DRbUnknownError) do
      @there.unknown_error
    end

    onecky = FailOnecky.new('3')

    assert_exception(FailOnecky::OneckyError) do
      @there.sample(onecky, 1, 2)
    end
  end

  def test_03
    assert_equal(8, @there.sum(1, 1, 1, 1, 1, 1, 1, 1))
    assert_exception(ArgumentError) do
      @there.sum(1, 1, 1, 1, 1, 1, 1, 1, 1)
    end
    assert_exception(DRb::DRbConnError) do
      @there.sum('1' * 2048)
    end
  end

  def test_04
    assert_respond_to('sum', @there)
    assert(!(@there.respond_to? "foobar"))
  end

  def test_05_eq
    a = @there.to_a[0]
    b = @there.to_a[0]
    assert(a.id != b.id)
    assert(a != b)
    assert(a.hash != b.hash)
    assert(! a.eql?(b))
    require 'drb/eq'
    assert(a == b)
    assert_equal(a, b)
    assert(a == @there)
    assert_equal(a.hash, b.hash)
    assert_equal(a.hash, @there.hash)
    assert(a.eql?(b))
    assert(a.eql?(@there))
  end

  def test_06_timeout
    ten = Onecky.new(10)
    assert_exception(TimeoutError) do
      @there.do_timeout(ten)
    end
    assert_exception(TimeoutError) do
      @there.do_timeout(ten)
    end
  end

  def test_07_public_private
    assert_no_exception() {
      begin
	@there.method_missing(:eval)
      rescue NameError
	assert_match($!.message, /^private method `eval'/)
      end
    }
    assert_no_exception() {
      begin
	@there.method_missing(:undefined_method_test)
      rescue NameError
	assert_match($!.message, /^undefined method `undefined_method_test'/)
      end
    }
    assert_exception(SecurityError) do
      @there.method_missing(:__send__, :to_s)
    end
  end

  def test_08_here
    ro = DRbObject.new(nil, DRb.uri)
    assert_kind_of(String, ro.to_s)
    
    ro = DRbObject.new_with_uri(DRb.uri)
    assert_kind_of(String, ro.to_s)
  end

  def uri_concat_option(uri, opt)
    "#{uri}?#{opt}"
  end

  def test_09_option
    uri = uri_concat_option(@there.__drburi, "foo")
    ro = DRbObject.new_with_uri(uri)
    assert_equal(ro.__drburi, @there.__drburi)
    assert_equal(3, ro.size)

    uri = uri_concat_option(@there.__drburi, "")
    ro = DRbObject.new_with_uri(uri)
    assert_equal(ro.__drburi, @there.__drburi)
    assert_equal(DRb::DRbURIOption.new(''), ro.__drbref)

    uri = uri_concat_option(@there.__drburi, "hello?world")
    ro = DRbObject.new_with_uri(uri)
    assert_equal(DRb::DRbURIOption.new('hello?world'), ro.__drbref)

    uri = uri_concat_option(@there.__drburi, "?hello?world")
    ro = DRbObject.new_with_uri(uri)
    assert_equal(DRb::DRbURIOption.new('?hello?world'), ro.__drbref)
  end

  def test_10_yield_undumped
    @there.xarray2_hash.each do |k, v|
      assert_kind_of(String, k)
      assert_kind_of(DRbObject, v)
    end
  end
end

class DRbYieldTest < RUNIT::TestCase
  def setup
    @ext = $manager.service('ut_drb.rb')
    @there = @ext.front
  end

  def teardown
    @ext.stop_service
  end

  def test_01_one
    one = nil
    @there.echo_yield_1([]) {|one|}
    assert_equal([], one)
    
    one = nil
    @there.echo_yield_1(1) {|one|}
    assert_equal(1, one)
    
    one = nil
    @there.echo_yield_1(nil) {|one|}
    assert_equal(nil, one)
  end

  def test_02_two
    one = two = nil
    @there.echo_yield_2([], []) {|one, two|}
    assert_equal([], one)
    assert_equal([], two)

    one = two = nil
    @there.echo_yield_2(1, 2) {|one, two|}
    assert_equal(1, one)
    assert_equal(2, two)

    one = two = nil
    @there.echo_yield_2(3, nil) {|one, two|}
    assert_equal(3, one)
    assert_equal(nil, two)
  end

  def test_03_many
    s = nil
    @there.echo_yield_0 {|*s|}
    assert_equal([], s)
    @there.echo_yield(nil) {|*s|}
    assert_equal([nil], s)
    @there.echo_yield(1) {|*s|}
    assert_equal([1], s)
    @there.echo_yield(1, 2) {|*s|}
    assert_equal([1, 2], s)
    @there.echo_yield(1, 2, 3) {|*s|}
    assert_equal([1, 2, 3], s)
    @there.echo_yield([], []) {|*s|}
    assert_equal([[], []], s)
    @there.echo_yield([]) {|*s|}
    if RUBY_VERSION >= '1.8'
      assert_equal([[]], s) # !
    else
      assert_equal([], s) # !
    end
  end

  def test_04_many_to_one
    s = nil
    @there.echo_yield_0 {|s|}
    assert_equal(nil, s)
    @there.echo_yield(nil) {|s|}
    assert_equal(nil, s)
    @there.echo_yield(1) {|s|}
    assert_equal(1, s)
    @there.echo_yield(1, 2) {|s|}
    assert_equal([1, 2], s)
    @there.echo_yield(1, 2, 3) {|s|}
    assert_equal([1, 2, 3], s)
    @there.echo_yield([], []) {|s|}
    assert_equal([[], []], s)
    @there.echo_yield([]) {|s|}
    assert_equal([], s)
  end

  def test_05_array_subclass
    @there.xarray_each {|x| assert_kind_of(XArray, x)}
    if RUBY_VERSION >= '1.8'
      @there.xarray_each {|*x| assert_kind_of(XArray, x[0])}
    end
  end
end

class RubyYieldTest < DRbYieldTest
  def echo_yield(*arg)
    yield(*arg)
  end

  def echo_yield_0
    yield
  end

  def echo_yield_1(a)
    yield(a)
  end

  def echo_yield_2(a, b)
    yield(a, b)
  end

  def xarray_each
    xary = [XArray.new([0])]
    xary.each do |x|
      yield(x)
    end
  end

  def setup
    @there = self
  end
  
  def teardown
  end
end

class Ruby18YieldTest < RubyYieldTest
  class YieldTest18
    def echo_yield(*arg, &proc)
      proc.call(*arg)
    end
    
    def echo_yield_0(&proc)
      proc.call
    end
    
    def echo_yield_1(a, &proc)
      proc.call(a)
    end
    
    def echo_yield_2(a, b, &proc)
      proc.call(a, b)
    end

    def xarray_each(&proc)
      xary = [XArray.new([0])]
      xary.each(&proc)
    end

  end

  def setup
    @there = YieldTest18.new
  end
end

class DRbAryTest < RUNIT::TestCase
  def setup
    @ext = $manager.service('ut_array.rb')
    @there = @ext.front
  end

  def teardown
    @ext.stop_service
  end

  def test_01
    assert_kind_of(DRb::DRbObject, @there)
  end

  def test_02_collect
    ary = @there.collect do |x| x + x end
    assert_kind_of(Array, ary)
    assert_equal([2, 4, 'IIIIII', 8, 'fivefive', 12], ary)
  end

  def test_03_redo
    ary = []
    count = 0
    @there.each do |x|
      count += 1
      ary.push x
      redo if count == 3
    end
    assert_equal([1, 2, 'III', 'III', 4, 'five', 6], ary)
  end

  def test_04_retry
    retried = false
    ary = []
    @there.each do |x|
      ary.push x
      if x == 4 && !retried
	retried = true
	retry
      end
    end
    assert_equal([1, 2, 'III', 4, 1, 2, 'III', 4, 'five', 6], ary)
  end

  def test_05_break
    ary = []
    @there.each do |x|
      ary.push x
      break if x == 4
    end
    assert_equal([1, 2, 'III', 4], ary)
  end

  def test_06_next
    ary = []
    @there.each do |x|
      next if String === x
      ary.push x
    end
    assert_equal([1, 2, 4, 6], ary)
  end

  if RUBY_VERSION >= '1.8'
    class_eval <<EOS
  def test_07_break_18
    ary = []
    result = @there.each do |x|
      ary.push x
      break(:done) if x == 4
    end
    assert_equal([1, 2, 'III', 4], ary)
    assert_equal(:done, result)
  end
EOS
  end

end

class DRbMServerTest < RUNIT::TestCase
  def setup
    @ext = $manager.service('ut_drb.rb')
    @there = @ext.front
    @server = (1..3).collect do |n|
      DRb::DRbServer.new(nil, Onecky.new(n.to_s))
    end
  end

  def teardown
    @server.each do |s|
      s.stop_service
    end
    @ext.stop_service
  end

  def test_01
    assert_equal(6, @there.sample(@server[0].front, @server[1].front, @server[2].front))
  end
end

class DRbReusePortTest < DRbAryTest
  def setup
    sleep 1
    @ext = $manager.service('ut_port.rb')
    @there = @ext.front
  end
end

class DRbSafe1Test < DRbAryTest
  def setup
    sleep 1
    @ext = $manager.service('ut_safe1.rb')
    @there = @ext.front
  end
end

class DRbEvalTest < RUNIT::TestCase
  def setup
    super
    sleep 1
    @ext = $manager.service('ut_eval.rb')
    @there = @ext.front
  end

  def teardown
    @ext.stop_service
  end
  
  def test_01_safe1_eval
    assert_exception(SecurityError) do
      @there.method_missing(:instance_eval, 'ENV.inspect')
    end

    assert_exception(SecurityError) do
      @there.method_missing(:send, :eval, 'ENV.inspect')
    end

    remote_class = @there.remote_class

    assert_exception(SecurityError) do
      remote_class.class_eval('ENV.inspect')
    end

    assert_exception(SecurityError) do
      remote_class.module_eval('ENV.inspect')
    end
  end
end

class DRbLargeTest < RUNIT::TestCase
  def setup
    sleep 1
    @ext = $manager.service('ut_large.rb')
    @there = @ext.front
  end

  def teardown
    @ext.stop_service
  end

  def test_01_large_ary
    ary = [2] * 10240
    assert_equal(10240, @there.size(ary))
    assert_equal(20480, @there.sum(ary))
  end

  def test_02_large_ary
    ary = ["Hello, World"] * 10240
    assert_equal(10240, @there.size(ary))
  end

  def test_03_large_ary
    ary = [Thread.current] * 10240
    assert_equal(10240, @there.size(ary))
  end

  def test_04_many_arg
    assert_exception(ArgumentError) {
      @there.arg_test(1, 2, 3, 4, 5, 6, 7, 8, 9, 0)
    }
  end

  def test_05_too_large_ary
    ary = ["Hello, World"] * 102400
    exception = nil
    begin
      @there.size(ary)      
    rescue StandardError
      exception = $!
    end
    assert_kind_of(StandardError, exception)
  end
end

if __FILE__ == $0
  $testservice = TestService.new
  $manager = $testservice.manager

  RUNIT::CUI::TestRunner.run(DRbCoreTest.suite)
  RUNIT::CUI::TestRunner.run(DRbEvalTest.suite)
  RUNIT::CUI::TestRunner.run(RubyYieldTest.suite)
  if RUBY_VERSION >= '1.8'
    RUNIT::CUI::TestRunner.run(Ruby18YieldTest.suite)
  end
  RUNIT::CUI::TestRunner.run(DRbYieldTest.suite)
  RUNIT::CUI::TestRunner.run(DRbAryTest.suite)
  RUNIT::CUI::TestRunner.run(DRbMServerTest.suite)
  RUNIT::CUI::TestRunner.run(DRbSafe1Test.suite)
  RUNIT::CUI::TestRunner.run(DRbReusePortTest.suite)
  RUNIT::CUI::TestRunner.run(DRbLargeTest.suite)
end

