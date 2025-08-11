# frozen_string_literal: false
require 'test/unit'

class TestRactor < Test::Unit::TestCase
  def test_shareability_of_iseq_proc
    y = nil.instance_eval do
      foo = []
      proc { foo }
    end
    assert_unshareable(y, /unshareable object \[\] from variable 'foo'/)

    y = [].instance_eval { proc { self } }
    assert_unshareable(y, /Proc's self is not shareable/)

    y = [].freeze.instance_eval { proc { self } }
    assert_make_shareable(y)
  end

  def test_shareability_of_curried_proc
    x = nil.instance_eval do
      foo = []
      proc { foo }.curry
    end
    assert_unshareable(x, /unshareable object \[\] from variable 'foo'/)

    x = nil.instance_eval do
      foo = 123
      proc { foo }.curry
    end
    assert_make_shareable(x)
  end

  def test_shareability_of_method_proc
    str = +""

    x = str.instance_exec { proc { to_s } }
    assert_unshareable(x, /Proc's self is not shareable/)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)

    str.freeze

    x = str.instance_exec { proc { to_s } }
    assert_make_shareable(x)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)
  end

  def test_shareability_error_uses_inspect
    x = (+"").instance_exec { method(:to_s) }
    def x.to_s
      raise "this should not be called"
    end
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)
  end

  def test_default_thread_group
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      Warning[:experimental] = false

      main_ractor_id = Thread.current.group.object_id
      ractor_id = Ractor.new { Thread.current.group.object_id }.value
      refute_equal main_ractor_id, ractor_id
    end;
  end

  def test_class_instance_variables
    assert_ractor(<<~'RUBY')
      # Once we're in multi-ractor mode, the codepaths
      # for class instance variables are a bit different.
      Ractor.new {}.value

      class TestClass
        @a = 1
        @b = 2
        @c = 3
        @d = 4
      end

      assert_equal 4, TestClass.remove_instance_variable(:@d)
      assert_nil TestClass.instance_variable_get(:@d)
      assert_equal 4, TestClass.instance_variable_set(:@d, 4)
      assert_equal 4, TestClass.instance_variable_get(:@d)
    RUBY
  end

  def test_struct_instance_variables
    assert_ractor(<<~'RUBY')
      StructIvar = Struct.new(:member) do
        def initialize(*)
          super
          @ivar = "ivar"
        end
        attr_reader :ivar
      end
      obj = StructIvar.new("member")
      obj_copy = Ractor.new { Ractor.receive }.send(obj).value
      assert_equal obj.ivar, obj_copy.ivar
      refute_same obj.ivar, obj_copy.ivar
      assert_equal obj.member, obj_copy.member
      refute_same obj.member, obj_copy.member
    RUBY
  end

  def test_fork_raise_isolation_error
    assert_ractor(<<~'RUBY')
      ractor = Ractor.new do
        Process.fork
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end if Process.respond_to?(:fork)

  def test_require_raises_and_no_ractor_belonging_issue
    assert_ractor(<<~'RUBY')
      require "tempfile"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("raise 'uh oh'")
      f.flush
      err_msg = Ractor.new(f.path) do |path|
        begin
          require path
        rescue RuntimeError => e
          e.message # had confirm belonging issue here
        else
          nil
        end
      end.value
      assert_equal "uh oh", err_msg
    RUBY
  end

  def test_require_non_string
    assert_ractor(<<~'RUBY')
      require "tempfile"
      require "pathname"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("")
      f.flush
      result = Ractor.new(f.path) do |path|
        require Pathname.new(path)
        "success"
      end.value
      assert_equal "success", result
    RUBY
  end

  # [Bug #21398]
  def test_port_receive_dnt_with_port_send
    assert_ractor(<<~'RUBY', timeout: 30)
      Warning[:experimental] = false

      THREADS = 2
      JOBS_PER_THREAD = 1000
      ARRAY_SIZE = 2000
      WORKERS = 2
      def ractor_job(job_count, array_size)
        port = Ractor::Port.new
        workers = WORKERS.times.map do |i|
          Ractor.new(port) do |job_port|
            while job = Ractor.receive
              result = job.map { |x| x * 2 }.sum
              job_port.send result
            end
          end
        end
        jobs = Array.new(job_count) { Array.new(array_size) { |i| i } }
        jobs.each_with_index do |job, i|
          w_idx = i % WORKERS
          workers[w_idx].send(job)
        end
        jobs.map do
          port.receive # dnt receive
        end
      end
      threads = []
      THREADS.times do
        threads << Thread.new do
          ractor_job(JOBS_PER_THREAD, ARRAY_SIZE)
        end
      end
      threads.each(&:join)
    RUBY
  end

  # [Bug #20346]
  def test_many_ractors_in_threads
    assert_ractor(<<~'RUBY')
      Warning[:experimental] = false

      N = 100
      ractors = N.times.map do
        Ractor.new do
          Ractor.recv # Ractor doesn't start until explicitly told to
          # Do some calculations
          fib = ->(x) { x < 2 ? 1 : fib.call(x - 1) + fib.call(x - 2) }
          fib.call(20)
        end
      end

      threads = ractors.map { |r| Thread.new { r.value } }
      ractors.each { |r| r.send(nil) }
      threads.each(&:join)
    RUBY
  end

  def assert_make_shareable(obj)
    refute Ractor.shareable?(obj), "object was already shareable"
    Ractor.make_shareable(obj)
    assert Ractor.shareable?(obj), "object didn't become shareable"
  end

  def assert_unshareable(obj, msg=nil, exception: Ractor::IsolationError)
    refute Ractor.shareable?(obj), "object is already shareable"
    assert_raise_with_message(exception, msg) do
      Ractor.make_shareable(obj)
    end
    refute Ractor.shareable?(obj), "despite raising, object became shareable"
  end
end
