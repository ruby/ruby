# frozen_string_literal: false
require_relative 'drbtest'

module DRbTests

class TestDRbCore < Test::Unit::TestCase
  include DRbCore

  def setup
    super
    setup_service 'ut_drb.rb'
  end
end

module DRbYield
  include DRbBase

  def test_01_one
    @there.echo_yield_1([]) {|one|
      assert_equal([], one)
    }

    @there.echo_yield_1(1) {|one|
      assert_equal(1, one)
    }

    @there.echo_yield_1(nil) {|one|
      assert_equal(nil, one)
    }
  end

  def test_02_two
    @there.echo_yield_2([], []) {|one, two|
      assert_equal([], one)
      assert_equal([], two)
    }

    @there.echo_yield_2(1, 2) {|one, two|
      assert_equal(1, one)
      assert_equal(2, two)
    }

    @there.echo_yield_2(3, nil) {|one, two|
      assert_equal(3, one)
      assert_equal(nil, two)
    }

    @there.echo_yield_1([:key, :value]) {|one, two|
      assert_equal(:key, one)
      assert_equal(:value, two)
    }
  end

  def test_03_many
    @there.echo_yield_0 {|*s|
      assert_equal([], s)
    }
    @there.echo_yield(nil) {|*s|
      assert_equal([nil], s)
    }
    @there.echo_yield(1) {|*s|
      assert_equal([1], s)
    }
    @there.echo_yield(1, 2) {|*s|
      assert_equal([1, 2], s)
    }
    @there.echo_yield(1, 2, 3) {|*s|
      assert_equal([1, 2, 3], s)
    }
    @there.echo_yield([], []) {|*s|
      assert_equal([[], []], s)
    }
    @there.echo_yield([]) {|*s|
      assert_equal([[]], s) # !
    }
  end

  def test_04_many_to_one
    @there.echo_yield_0 {|*s|
      assert_equal([], s)
    }
    @there.echo_yield(nil) {|*s|
      assert_equal([nil], s)
    }
    @there.echo_yield(1) {|*s|
      assert_equal([1], s)
    }
    @there.echo_yield(1, 2) {|*s|
      assert_equal([1, 2], s)
    }
    @there.echo_yield(1, 2, 3) {|*s|
      assert_equal([1, 2, 3], s)
    }
    @there.echo_yield([], []) {|*s|
      assert_equal([[], []], s)
    }
    @there.echo_yield([]) {|*s|
      assert_equal([[]], s)
    }
  end

  def test_05_array_subclass
    @there.xarray_each {|x| assert_kind_of(XArray, x)}
    @there.xarray_each {|*x| assert_kind_of(XArray, x[0])}
  end
end

class TestDRbYield < Test::Unit::TestCase
  include DRbYield

  def setup
    super
    setup_service 'ut_drb.rb'
  end
end

class TestDRbRubyYield < Test::Unit::TestCase
  include DRbYield

  def setup
    @there = self
    super
  end

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

end

class TestDRbRuby18Yield < Test::Unit::TestCase
  include DRbYield

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
    super
  end
end

class TestDRbAry < Test::Unit::TestCase
  include DRbAry

  def setup
    super
    setup_service 'ut_array.rb'
  end
end

class TestDRbMServer < Test::Unit::TestCase
  include DRbBase

  def setup
    super
    setup_service 'ut_drb.rb'
    @server = (1..3).collect do |n|
      DRb::DRbServer.new("druby://localhost:0", Onecky.new(n.to_s))
    end
  end

  def teardown
    @server.each do |s|
      s.stop_service
    end
    super
  end

  def test_01
    assert_equal(6, @there.sample(@server[0].front, @server[1].front, @server[2].front))
  end
end

class TestDRbSafe1 < Test::Unit::TestCase
  include DRbAry
  def setup
    super
    setup_service 'ut_safe1.rb'
  end
end

class TestDRbLarge < Test::Unit::TestCase
  include DRbBase

  def setup
    super
    setup_service 'ut_large.rb'
  end

  def test_01_large_ary
    ary = [2] * 10240
    assert_equal(10240, @there.size(ary))
    assert_equal(20480, @there.sum(ary))
    assert_equal(2 ** 10240, @there.multiply(ary))
    assert_equal(2, @there.avg(ary))
    assert_equal(2, @there.median(ary))
  end

  def test_02_large_ary
    ary = ["Hello, World"] * 10240
    assert_equal(10240, @there.size(ary))
    assert_equal(ary[0..ary.length].inject(:+), @there.sum(ary))
    assert_raise(TypeError) {@there.multiply(ary)}
    assert_raise(TypeError) {@there.avg(ary)}
    assert_raise(TypeError) {@there.median(ary)}
  end

  def test_03_large_ary
    ary = [Thread.current] * 10240
    assert_equal(10240, @there.size(ary))
  end

  def test_04_many_arg
    assert_raise(DRb::DRbConnError) {
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

  def test_06_array_operations
    ary = [1,50,3,844,7,45,23]
    assert_equal(7, @there.size(ary))
    assert_equal(973, @there.sum(ary))
    assert_equal(917217000, @there.multiply(ary))
    assert_equal(139.0, @there.avg(ary))
    assert_equal(23.0, @there.median(ary))

    ary2 = [1,2,3,4]
    assert_equal(4, @there.size(ary2))
    assert_equal(10, @there.sum(ary2))
    assert_equal(24, @there.multiply(ary2))
    assert_equal(2.5, @there.avg(ary2))
    assert_equal(2.5, @there.median(ary2))

  end

  def test_07_one_element_array
    ary = [50]
    assert_equal(1, @there.size(ary))
    assert_equal(50, @there.sum(ary))
    assert_equal(50, @there.multiply(ary))
    assert_equal(50.0, @there.avg(ary))
    assert_equal(50.0, @there.median(ary))
  end

  def test_08_empty_array
    ary = []
    assert_equal(0, @there.size(ary))
    assert_equal(nil, @there.sum(ary))
    assert_equal(nil, @there.multiply(ary))
    assert_equal(nil, @there.avg(ary))
    assert_equal(nil, @there.median(ary))
  end
end

class TestBug4409 < Test::Unit::TestCase
  include DRbBase

  def setup
    super
    setup_service 'ut_eq.rb'
  end

  def test_bug4409
    foo = @there.foo
    assert_operator(@there, :foo?, foo)
  end
end

class TestDRbAnyToS < Test::Unit::TestCase
  class BO < BasicObject
  end

  def test_any_to_s
    server = DRb::DRbServer.new('druby://localhost:0')
    server.singleton_class.send(:public, :any_to_s)
    assert_equal("foo:String", server.any_to_s("foo"))
    assert_match(/\A#<DRbTests::TestDRbAnyToS::BO:0x[0-9a-f]+>\z/, server.any_to_s(BO.new))
    server.stop_service
    server.thread.join
    DRb::DRbConn.stop_pool
  end
end

class TestDRbTCP < Test::Unit::TestCase
  def test_immediate_close
    server = DRb::DRbServer.new('druby://localhost:0')
    host, port, = DRb::DRbTCPSocket.send(:parse_uri, server.uri)
    socket = TCPSocket.open host, port
    socket.shutdown
    socket.close
    client = DRb::DRbTCPSocket.new(server.uri, socket)
    assert client
  ensure
    client&.close
    socket&.close
    server.stop_service
    server.thread.join
    DRb::DRbConn.stop_pool
  end
end

class TestBug16634 < Test::Unit::TestCase
  include DRbBase

  def setup
    super
    setup_service 'ut_drb.rb'
  end

  def test_bug16634
    assert_equal(42, @there.keyword_test1(a: 42))
    assert_equal("default", @there.keyword_test2)
    assert_equal(42, @there.keyword_test2(b: 42))
    assert_equal({:a=>42, :b=>42}, @there.keyword_test3(a: 42, b: 42))
  end
end

end
