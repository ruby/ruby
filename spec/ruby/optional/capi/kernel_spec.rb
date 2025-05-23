require_relative 'spec_helper'
require_relative 'fixtures/kernel'

kernel_path = load_extension("kernel")

class CApiKernelSpecs::Exc < StandardError
end
exception_class = CApiKernelSpecs::Exc

describe "C-API Kernel function" do
  before :each do
    @s = CApiKernelSpecs.new
  end

  after :each do
    @s.rb_errinfo.should == nil
  end

  describe "rb_block_given_p" do
    it "returns false if no block is passed" do
      @s.should_not.rb_block_given_p
    end

    it "returns true if a block is passed" do
      (@s.rb_block_given_p { puts "FOO" } ).should == true
    end
  end

  describe "rb_need_block" do
    it "raises a LocalJumpError if no block is given" do
      -> { @s.rb_need_block }.should raise_error(LocalJumpError)
    end

    it "does not raise a LocalJumpError if a block is given" do
      @s.rb_need_block { }.should == nil
    end
  end

  describe "rb_block_call" do
    before :each do
      ScratchPad.record []
    end

    it "calls the block with a single argument" do
      ary = [1, 3, 5]
      @s.rb_block_call(ary).should == [2, 4, 6]
    end

    it "calls the block with multiple arguments in argc / argv" do
      ary = [1, 3, 5]
      @s.rb_block_call_multi_arg(ary).should == 9
    end

    it "calls the method with no function callback and no block" do
      ary = [1, 3, 5]
      @s.rb_block_call_no_func(ary).should be_kind_of(Enumerator)
    end

    it "calls the method with no function callback and a block" do
      ary = [1, 3, 5]
      @s.rb_block_call_no_func(ary) do |i|
        i + 1
      end.should == [2, 4, 6]
    end

    it "can pass extra data to the function" do
      ary = [3]
      @s.rb_block_call_extra_data(ary).should equal(ary)
    end
  end

  describe "rb_frame_this_func" do
    it "returns the name of the method called" do
      @s.rb_frame_this_func_test.should == :rb_frame_this_func_test
      @s.rb_frame_this_func_test_again.should == :rb_frame_this_func_test_again
    end
  end

  describe "rb_raise" do
    it "raises an exception" do
      -> { @s.rb_raise({}) }.should raise_error(TypeError)
    end

    it "terminates the function at the point it was called" do
      h = {}
      -> { @s.rb_raise(h) }.should raise_error(TypeError)
      h[:stage].should == :before
    end

    it "re-raises a rescued exception" do
      -> do
        begin
          raise StandardError, "aaa"
        rescue Exception
          begin
            @s.rb_raise({})
          rescue TypeError
          end

          # should raise StandardError "aaa"
          raise
        end
      end.should raise_error(StandardError, "aaa")
    end
  end

  describe "rb_throw" do
    before :each do
      ScratchPad.record []
    end

    it "sets the return value of the catch block to the specified value" do
      catch(:foo) do
        @s.rb_throw(:return_value)
      end.should == :return_value
    end

    it "terminates the function at the point it was called" do
      catch(:foo) do
        ScratchPad << :before_throw
        @s.rb_throw(:thrown_value)
        ScratchPad << :after_throw
      end.should == :thrown_value
      ScratchPad.recorded.should == [:before_throw]
    end

    it "raises an ArgumentError if there is no catch block for the symbol" do
      -> { @s.rb_throw(nil) }.should raise_error(ArgumentError)
    end
  end

  describe "rb_throw_obj" do
    before :each do
      ScratchPad.record []
      @tag = Object.new
    end

    it "sets the return value of the catch block to the specified value" do
      catch(@tag) do
        @s.rb_throw_obj(@tag, :thrown_value)
      end.should == :thrown_value
    end

    it "terminates the function at the point it was called" do
      catch(@tag) do
        ScratchPad << :before_throw
        @s.rb_throw_obj(@tag, :thrown_value)
        ScratchPad << :after_throw
      end.should == :thrown_value
      ScratchPad.recorded.should == [:before_throw]
    end

    it "raises an ArgumentError if there is no catch block for the symbol" do
      -> { @s.rb_throw(nil) }.should raise_error(ArgumentError)
    end
  end

  describe "rb_warn" do
    it "prints a message to $stderr if $VERBOSE evaluates to true" do
      -> {
        @s.rb_warn("This is a warning")
      }.should complain(/warning: This is a warning/, verbose: true)
    end

    it "prints a message to $stderr if $VERBOSE evaluates to false" do
      -> {
        @s.rb_warn("This is a warning")
      }.should complain(/warning: This is a warning/, verbose: false)
    end
  end

  describe "rb_sys_fail" do
    it "raises an exception from the value of errno" do
      -> do
        @s.rb_sys_fail("additional info")
      end.should raise_error(SystemCallError, /additional info/)
    end

    it "can take a NULL message" do
      -> do
        @s.rb_sys_fail(nil)
      end.should raise_error(Errno::EPERM)
    end
  end

  describe "rb_syserr_fail" do
    it "raises an exception from the given error" do
      -> do
        @s.rb_syserr_fail(Errno::EINVAL::Errno, "additional info")
      end.should raise_error(Errno::EINVAL, "Invalid argument - additional info")
    end

    it "can take a NULL message" do
      -> do
        @s.rb_syserr_fail(Errno::EINVAL::Errno, nil)
      end.should raise_error(Errno::EINVAL, "Invalid argument")
    end

    it "uses some kind of string as message when errno is unknown" do
      -> { @s.rb_syserr_fail(-10, nil) }.should raise_error(SystemCallError, /[[:graph:]]+/)
    end
  end

  describe "rb_syserr_fail_str" do
    it "raises an exception from the given error" do
      -> do
        @s.rb_syserr_fail_str(Errno::EINVAL::Errno, "additional info")
      end.should raise_error(Errno::EINVAL, "Invalid argument - additional info")
    end

    it "can take nil as a message" do
      -> do
        @s.rb_syserr_fail_str(Errno::EINVAL::Errno, nil)
      end.should raise_error(Errno::EINVAL, "Invalid argument")
    end

    it "uses some kind of string as message when errno is unknown" do
      -> { @s.rb_syserr_fail_str(-10, nil) }.should raise_error(SystemCallError, /[[:graph:]]+/)
    end
  end

  describe "rb_yield" do
    it "yields passed argument" do
      ret = nil
      @s.rb_yield(1) { |z| ret = z }
      ret.should == 1
    end

    it "returns the result from block evaluation" do
      @s.rb_yield(1) { |z| z * 1000 }.should == 1000
    end

    it "raises LocalJumpError when no block is given" do
      -> { @s.rb_yield(1) }.should raise_error(LocalJumpError)
    end

    it "rb_yield to a block that breaks does not raise an error" do
      @s.rb_yield(1) { break }.should == nil
    end

    it "rb_yield to a block that breaks with a value returns the value" do
      @s.rb_yield(1) { break 73 }.should == 73
    end

    it "rb_yield through a callback to a block that breaks with a value returns the value" do
      @s.rb_yield_indirected(1) { break 73 }.should == 73
    end

    it "rb_yield to block passed to enumerator" do
      enum_class = Class.new do
        include Enumerable
      end
      @s.rb_yield_define_each(enum_class)
      res = enum_class.new.collect { |i| i * 2}
      res.should == [0, 2, 4, 6]
    end

  end

  describe "rb_yield_values" do
    it "yields passed arguments" do
      ret = nil
      @s.rb_yield_values(1, 2) { |x, y| ret = x + y }
      ret.should == 3
    end

    it "returns the result from block evaluation" do
      @s.rb_yield_values(1, 2) { |x, y| x + y }.should == 3
    end

    it "raises LocalJumpError when no block is given" do
      -> { @s.rb_yield_splat([1, 2]) }.should raise_error(LocalJumpError)
    end
  end

  describe "rb_yield_values2" do
    it "yields passed arguments" do
      ret = nil
      @s.rb_yield_values2([1, 2]) { |x, y| ret = x + y }
      ret.should == 3
    end

    it "returns the result from block evaluation" do
      @s.rb_yield_values2([1, 2]) { |x, y| x + y }.should == 3
    end
  end

  describe "rb_yield_splat" do
    it "yields with passed array's contents" do
      ret = nil
      @s.rb_yield_splat([1, 2]) { |x, y| ret = x + y }
      ret.should == 3
    end

    it "returns the result from block evaluation" do
      @s.rb_yield_splat([1, 2]) { |x, y| x + y }.should == 3
    end

    it "passes arguments to a block accepting splatted args" do
      @s.rb_yield_splat([1, 2]) { |*v| v }.should == [1, 2]
    end

    it "raises LocalJumpError when no block is given" do
      -> { @s.rb_yield_splat([1, 2]) }.should raise_error(LocalJumpError)
    end
  end

  describe "rb_protect" do
    it "will run a function with an argument" do
      proof = [] # Hold proof of work performed after the yield.
      res = @s.rb_protect_yield(77, proof) { |x| x + 1 }
      res.should == 78
      proof[0].should == 23
    end

    it "will allow cleanup code to run after break" do
      proof = [] # Hold proof of work performed after the yield.
      @s.rb_protect_yield(77, proof) { |x| break }
      proof[0].should == 23
    end

    it "will allow cleanup code to run after break with value" do
      proof = [] # Hold proof of work performed after the yield.
      res = @s.rb_protect_yield(77, proof) { |x| break x + 1 }
      res.should == 78
      proof[0].should == 23
    end

    it "will allow cleanup code to run after a raise" do
      proof = [] # Hold proof of work performed after the yield.
      -> do
        @s.rb_protect_yield(77, proof) { |x| raise NameError }
      end.should raise_error(NameError)
      proof[0].should == 23
    end

    it "will return nil if an error was raised" do
      proof = [] # Hold proof of work performed after the yield.
      -> do
        @s.rb_protect_yield(77, proof) { |x| raise NameError }
      end.should raise_error(NameError)
      proof[0].should == 23
      proof[1].should == nil
    end

    it "accepts NULL as status and returns nil if it failed" do
      @s.rb_protect_null_status(42) { |x| x + 1 }.should == 43
      @s.rb_protect_null_status(42) { |x| raise NameError }.should == nil
      @s.rb_errinfo().should.is_a? NameError
    ensure
      @s.rb_set_errinfo(nil)
    end

    it "populates rb_errinfo() with the captured exception" do
      proof = []
      @s.rb_protect_ignore_status(77, proof) { |x| raise NameError }
      @s.rb_errinfo().should.is_a? NameError
      # Note: on CRuby $! is the NameError here, but not clear if that is desirable or bug
      proof[0].should == 23
      proof[1].should == nil
    ensure
      @s.rb_set_errinfo(nil)
    end

  end

  describe "rb_eval_string_protect" do
    it "will evaluate the given string" do
      proof = []
      res = @s.rb_eval_string_protect('1 + 7', proof)
      proof.should == [23, 8]
    end

    it "will allow cleanup code to be run when an exception is raised" do
      proof = []
      -> do
        @s.rb_eval_string_protect('raise RuntimeError', proof)
      end.should raise_error(RuntimeError)
      proof.should == [23, nil]
    end
  end

  describe "rb_rescue" do
    before :each do
      @proc = -> x { x }
      @rescue_proc_returns_sentinel = -> *_ { :rescue_proc_executed }
      @rescue_proc_returns_arg = -> *a { a }
      @arg_error_proc = -> *_ { raise ArgumentError, '' }
      @std_error_proc = -> *_ { raise StandardError, '' }
      @exc_error_proc = -> *_ { raise Exception, '' }
    end

    it "executes passed function" do
      @s.rb_rescue(@proc, :no_exc, @rescue_proc_returns_arg, :exc).should == :no_exc
    end

    it "executes the passed 'rescue function' if a StandardError exception is raised" do
      @s.rb_rescue(@arg_error_proc, nil, @rescue_proc_returns_sentinel, :exc).should == :rescue_proc_executed
      @s.rb_rescue(@std_error_proc, nil, @rescue_proc_returns_sentinel, :exc).should == :rescue_proc_executed
    end

    it "passes the user supplied argument to the 'rescue function' if a StandardError exception is raised" do
      arg1, _ = @s.rb_rescue(@arg_error_proc, nil, @rescue_proc_returns_arg, :exc1)
      arg1.should == :exc1

      arg2, _ = @s.rb_rescue(@std_error_proc, nil, @rescue_proc_returns_arg, :exc2)
      arg2.should == :exc2
    end

    it "passes the raised exception to the 'rescue function' if a StandardError exception is raised" do
      _, exc1 = @s.rb_rescue(@arg_error_proc, nil, @rescue_proc_returns_arg, :exc)
      exc1.class.should == ArgumentError

      _, exc2 = @s.rb_rescue(@std_error_proc, nil, @rescue_proc_returns_arg, :exc)
      exc2.class.should == StandardError
    end

    it "raises an exception if passed function raises an exception other than StandardError" do
      -> { @s.rb_rescue(@exc_error_proc, nil, @rescue_proc_returns_arg, nil) }.should raise_error(Exception)
    end

    it "raises an exception if any exception is raised inside the 'rescue function'" do
      -> { @s.rb_rescue(@std_error_proc, nil, @std_error_proc, nil) }.should raise_error(StandardError)
    end

    it "sets $! and rb_errinfo() during the 'rescue function' execution" do
      @s.rb_rescue(-> *_ { raise exception_class, '' }, nil, -> _, exc {
        exc.should.is_a?(exception_class)
        $!.should.equal?(exc)
        @s.rb_errinfo.should.equal?(exc)
      }, nil)

      @s.rb_rescue(-> _ { @s.rb_raise({}) }, nil, -> _, exc {
        exc.should.is_a?(TypeError)
        $!.should.equal?(exc)
        @s.rb_errinfo.should.equal?(exc)
      }, nil)

      $!.should == nil
      @s.rb_errinfo.should == nil
    end

    it "returns the break value if the passed function yields to a block with a break" do
      def proc_caller
        @s.rb_rescue(-> *_ { yield }, nil, @proc, nil)
      end

      proc_caller { break :value }.should == :value
    end

    it "returns nil if the 'rescue function' is null" do
      @s.rb_rescue(@std_error_proc, nil, nil, nil).should == nil
    end
  end

  describe "rb_rescue2" do
    it "only rescues if one of the passed exceptions is raised" do
      proc = -> x, _exc { x }
      arg_error_proc = -> *_ { raise ArgumentError, '' }
      run_error_proc = -> *_ { raise RuntimeError, '' }
      type_error_proc = -> *_ { raise Exception, 'custom error' }
      @s.rb_rescue2(arg_error_proc, :no_exc, proc, :exc, ArgumentError, RuntimeError).should == :exc
      @s.rb_rescue2(run_error_proc, :no_exc, proc, :exc, ArgumentError, RuntimeError).should == :exc
      -> {
        @s.rb_rescue2(type_error_proc, :no_exc, proc, :exc, ArgumentError, RuntimeError)
      }.should raise_error(Exception, 'custom error')
    end

    it "raises TypeError if one of the passed exceptions is not a Module" do
      -> {
        @s.rb_rescue2(-> *_ { raise RuntimeError, "foo" }, :no_exc, -> x { x }, :exc, Object.new, 42)
      }.should raise_error(TypeError, /class or module required/)
    end

    it "sets $! and rb_errinfo() during the 'rescue function' execution" do
      @s.rb_rescue2(-> *_ { raise exception_class, '' }, :no_exc, -> _, exc {
        exc.should.is_a?(exception_class)
        $!.should.equal?(exc)
        @s.rb_errinfo.should.equal?(exc)
      }, :exc, exception_class, ScriptError)

      @s.rb_rescue2(-> *_ { @s.rb_raise({}) }, :no_exc, -> _, exc {
        exc.should.is_a?(TypeError)
        $!.should.equal?(exc)
        @s.rb_errinfo.should.equal?(exc)
      }, :exc, TypeError, ArgumentError)

      $!.should == nil
      @s.rb_errinfo.should == nil
    end
  end

  describe "rb_catch" do
    before :each do
      ScratchPad.record []
    end

    it "executes passed function" do
      @s.rb_catch("foo", -> { 1 }).should == 1
    end

    it "terminates the function at the point it was called" do
      proc = -> do
        ScratchPad << :before_throw
        throw :thrown_value
        ScratchPad << :after_throw
      end
      @s.rb_catch("thrown_value", proc).should be_nil
      ScratchPad.recorded.should == [:before_throw]
    end

    it "raises an ArgumentError if the throw symbol isn't caught" do
      -> { @s.rb_catch("foo", -> { throw :bar }) }.should raise_error(ArgumentError)
    end
  end

  describe "rb_catch_obj" do

    before :each do
      ScratchPad.record []
      @tag = Object.new
    end

    it "executes passed function" do
      @s.rb_catch_obj(@tag, -> { 1 }).should == 1
    end

    it "terminates the function at the point it was called" do
      proc = -> do
        ScratchPad << :before_throw
        throw @tag
        ScratchPad << :after_throw
      end
      @s.rb_catch_obj(@tag, proc).should be_nil
      ScratchPad.recorded.should == [:before_throw]
    end

    it "raises an ArgumentError if the throw symbol isn't caught" do
      -> { @s.rb_catch("foo", -> { throw :bar }) }.should raise_error(ArgumentError)
    end
  end

  describe "rb_category_warn" do
    it "emits a warning into stderr" do
      Warning[:deprecated] = true

      -> {
        @s.rb_category_warn_deprecated
      }.should complain(/warning: foo/, verbose: true)
    end

    it "supports printf format modifiers" do
      Warning[:deprecated] = true

      -> {
        @s.rb_category_warn_deprecated_with_integer_extra_value(42)
      }.should complain(/warning: foo 42/, verbose: true)
    end

    it "does not emits a warning when a category is disabled" do
      Warning[:deprecated] = false

      -> {
        @s.rb_category_warn_deprecated
      }.should_not complain(verbose: true)
    end

    it "does not emits a warning when $VERBOSE is nil" do
      Warning[:deprecated] = true

      -> {
        @s.rb_category_warn_deprecated
      }.should_not complain(verbose: nil)
    end
  end

  describe "rb_ensure" do
    it "executes passed function and returns its value" do
      proc = -> x { x }
      @s.rb_ensure(proc, :proc, proc, :ensure_proc).should == :proc
    end

    it "executes passed 'ensure function' when no exception is raised" do
      foo = nil
      proc = -> *_ { }
      ensure_proc = -> x { foo = x }
      @s.rb_ensure(proc, nil, ensure_proc, :foo)
      foo.should == :foo
    end

    it "executes passed 'ensure function' when an exception is raised" do
      foo = nil
      raise_proc = -> _ { raise exception_class }
      ensure_proc = -> x { foo = x }
      -> {
        @s.rb_ensure(raise_proc, nil, ensure_proc, :foo)
      }.should raise_error(exception_class)
      foo.should == :foo
    end

    it "sets $! and rb_errinfo() during the 'ensure function' execution" do
      -> {
        @s.rb_ensure(-> _ { raise exception_class }, nil, -> _ {
          $!.should.is_a?(exception_class)
          @s.rb_errinfo.should.is_a?(exception_class)
        }, nil)
      }.should raise_error(exception_class)

      -> {
        @s.rb_ensure(-> _ { @s.rb_raise({}) }, nil, -> _ {
          $!.should.is_a?(TypeError)
          @s.rb_errinfo.should.is_a?(TypeError)
        }, nil)
      }.should raise_error(TypeError)

      $!.should == nil
      @s.rb_errinfo.should == nil
    end

    it "raises the same exception raised inside passed function" do
      raise_proc = -> *_ { raise RuntimeError, 'foo' }
      proc = -> *_ { }
      -> { @s.rb_ensure(raise_proc, nil, proc, nil) }.should raise_error(RuntimeError, 'foo')
    end
  end

  describe "rb_eval_string" do
    it "evaluates a string of ruby code" do
      @s.rb_eval_string("1+1").should == 2
    end

    it "captures local variables when called within a method" do
      a = 2
      @s.rb_eval_string("a+1").should == 3
    end
  end

  describe "rb_eval_cmd_kw" do
    it "evaluates a string of ruby code" do
      @s.rb_eval_cmd_kw("1+1", [], 0).should == 2
    end

    it "calls a proc with the supplied arguments" do
      @s.rb_eval_cmd_kw(-> *x { x.map { |i| i + 1 } }, [1, 3, 7], 0).should == [2, 4, 8]
    end

    it "calls a proc with keyword arguments if kw_splat is non zero" do
      a_proc = -> *x, **y {
        res = x.map { |i| i + 1 }
        y.each { |k, v| res << k; res << v }
        res
      }
      @s.rb_eval_cmd_kw(a_proc, [1, 3, 7, {a: 1, b: 2, c: 3}], 1).should == [2, 4, 8, :a, 1, :b, 2, :c, 3]
    end
  end

  describe "rb_block_proc" do
    it "converts the implicit block into a proc" do
      proc = @s.rb_block_proc { 1+1 }
      proc.should be_kind_of(Proc)
      proc.call.should == 2
      proc.should_not.lambda?
    end

    it "passes through an existing lambda and does not convert to a proc" do
      b = -> { 1+1 }
      proc = @s.rb_block_proc(&b)
      proc.should equal(b)
      proc.call.should == 2
      proc.should.lambda?
    end
  end

  describe "rb_block_lambda" do
    it "converts the implicit block into a lambda" do
      proc = @s.rb_block_lambda { 1+1 }
      proc.should be_kind_of(Proc)
      proc.call.should == 2
      proc.should.lambda?
    end

    it "passes through an existing Proc and does not convert to a lambda" do
      b = proc { 1+1 }
      proc = @s.rb_block_lambda(&b)
      proc.should equal(b)
      proc.call.should == 2
      proc.should_not.lambda?
    end
  end

  describe "rb_exec_recursive" do
    it "detects recursive invocations of a method and indicates as such" do
      s = "hello"
      @s.rb_exec_recursive(s).should == s
    end
  end

  describe "rb_set_end_proc" do
    it "runs a C function on shutdown" do
      ruby_exe("require #{kernel_path.inspect}; CApiKernelSpecs.new.rb_set_end_proc(STDOUT)").should == "in write_io"
    end
  end

  describe "rb_f_sprintf" do
    it "returns a string according to format and arguments" do
      @s.rb_f_sprintf(["%d %f %s", 10, 2.5, "test"]).should == "10 2.500000 test"
    end
  end

  describe "rb_make_backtrace" do
    it "returns a caller backtrace" do
      backtrace = @s.rb_make_backtrace
      lines = backtrace.select {|l| l =~ /#{__FILE__}/ }
      lines.should_not be_empty
    end
  end

  describe "rb_funcallv" do
    def empty
      42
    end

    def sum(a, b)
      a + b
    end

    it "calls a method" do
      @s.rb_funcallv(self, :empty, []).should == 42
      @s.rb_funcallv(self, :sum, [1, 2]).should == 3
    end

    it "calls a private method" do
      object = CApiKernelSpecs::ClassWithPrivateMethod.new
      @s.rb_funcallv(object, :private_method, []).should == :private
    end

    it "calls a protected method" do
      object = CApiKernelSpecs::ClassWithProtectedMethod.new
      @s.rb_funcallv(object, :protected_method, []).should == :protected
    end
  end

  describe "rb_funcallv_kw" do
    it "passes keyword arguments to the callee" do
      def m(*args, **kwargs)
        [args, kwargs]
      end

      @s.rb_funcallv_kw(self, :m, [{}]).should == [[], {}]
      @s.rb_funcallv_kw(self, :m, [{a: 1}]).should == [[], {a: 1}]
      @s.rb_funcallv_kw(self, :m, [{b: 2}, {a: 1}]).should == [[{b: 2}], {a: 1}]
      @s.rb_funcallv_kw(self, :m, [{b: 2}, {}]).should == [[{b: 2}], {}]
    end

    it "calls a private method" do
      object = CApiKernelSpecs::ClassWithPrivateMethod.new
      @s.rb_funcallv_kw(object, :private_method, [{}]).should == :private
    end

    it "calls a protected method" do
      object = CApiKernelSpecs::ClassWithProtectedMethod.new
      @s.rb_funcallv_kw(object, :protected_method, [{}]).should == :protected
    end

    it "raises TypeError if the last argument is not a Hash" do
      def m(*args, **kwargs)
        [args, kwargs]
      end

      -> {
        @s.rb_funcallv_kw(self, :m, [42])
      }.should raise_error(TypeError, 'no implicit conversion of Integer into Hash')
    end
  end

  describe "rb_keyword_given_p" do
    it "returns whether keywords were given to the C extension method" do
      h = {a: 1}
      empty = {}
      @s.rb_keyword_given_p(a: 1).should == true
      @s.rb_keyword_given_p("foo" => "bar").should == true
      @s.rb_keyword_given_p(**h).should == true

      @s.rb_keyword_given_p(h).should == false
      @s.rb_keyword_given_p().should == false
      @s.rb_keyword_given_p(**empty).should == false

      @s.rb_funcallv_kw(@s, :rb_keyword_given_p, [{a: 1}]).should == true
      @s.rb_funcallv_kw(@s, :rb_keyword_given_p, [{}]).should == false
    end
  end

  describe "rb_funcallv_public" do
    before :each do
      @obj = Object.new
      class << @obj
        def method_public; :method_public end
        def method_private; :method_private end
        private :method_private
      end
    end

    it "calls a public method" do
      @s.rb_funcallv_public(@obj, :method_public).should == :method_public
    end

    it "does not call a private method" do
      -> { @s.rb_funcallv_public(@obj, :method_private) }.should raise_error(NoMethodError, /private/)
    end
  end

  describe 'rb_funcall' do
    before :each do
      @obj = Object.new
      class << @obj
        def many_args(*args)
          args
        end
      end
    end

    it "can call a public method with 15 arguments" do
      @s.rb_funcall_many_args(@obj, :many_args).should == 15.downto(1).to_a
    end
  end

  describe 'rb_funcall_with_block' do
    it "calls a method with block" do
      @obj = Object.new
      class << @obj
        def method_public(*args); [args, yield] end
      end

      @s.rb_funcall_with_block(@obj, :method_public, [1, 2], proc { :result }).should == [[1, 2], :result]
    end

    it "does not call a private method" do
      object = CApiKernelSpecs::ClassWithPrivateMethod.new

      -> {
        @s.rb_funcall_with_block(object, :private_method, [], proc { })
      }.should raise_error(NoMethodError, /private/)
    end

    it "does not call a protected method" do
      object = CApiKernelSpecs::ClassWithProtectedMethod.new

      -> {
        @s.rb_funcall_with_block(object, :protected_method, [], proc { })
      }.should raise_error(NoMethodError, /protected/)
    end
  end

  describe 'rb_funcall_with_block_kw' do
    it "calls a method with keyword arguments and a block" do
      @obj = Object.new
      class << @obj
        def method_public(*args, **kw, &block); [args, kw, block.call] end
      end

      @s.rb_funcall_with_block_kw(@obj, :method_public, [1, 2, {a: 2}], proc { :result }).should == [[1, 2], {a: 2}, :result]
    end

    it "does not call a private method" do
      object = CApiKernelSpecs::ClassWithPrivateMethod.new

      -> {
        @s.rb_funcall_with_block_kw(object, :private_method, [{}], proc { })
      }.should raise_error(NoMethodError, /private/)
    end

    it "does not call a protected method" do
      object = CApiKernelSpecs::ClassWithProtectedMethod.new

      -> {
        @s.rb_funcall_with_block_kw(object, :protected_method, [{}], proc { })
      }.should raise_error(NoMethodError, /protected/)
    end
  end

  describe "rb_check_funcall" do
    it "calls a method" do
      @s.rb_check_funcall(1, :+, [2]).should == 3
    end

    it "returns Qundef if the method is not defined" do
      obj = Object.new
      @s.rb_check_funcall(obj, :foo, []).should == :Qundef
    end

    it "uses #respond_to? to check if the method is defined" do
      ScratchPad.record []
      obj = Object.new
      def obj.respond_to?(name, priv)
        ScratchPad << name
        name == :foo || super
      end
      def obj.method_missing(name, *args)
        name == :foo ? [name, 42] : super
      end
      @s.rb_check_funcall(obj, :foo, []).should == [:foo, 42]
      ScratchPad.recorded.should == [:foo]
    end

    it "calls a private method" do
      object = CApiKernelSpecs::ClassWithPrivateMethod.new
      @s.rb_check_funcall(object, :private_method, []).should == :private
    end

    it "calls a protected method" do
      object = CApiKernelSpecs::ClassWithProtectedMethod.new
      @s.rb_check_funcall(object, :protected_method, []).should == :protected
    end
  end

  describe "rb_str_format" do
    it "returns a string according to format and arguments" do
      @s.rb_str_format(3, [10, 2.5, "test"], "%d %f %s").should == "10 2.500000 test"
    end
  end
end
