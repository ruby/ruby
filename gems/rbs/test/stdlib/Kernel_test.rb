require_relative "test_helper"

require "securerandom"

class KernelTest < StdlibTest
  target Kernel
  using hook.refinement

  def test_caller
    caller(1, 2)
    caller(1)
    caller(1..2)
    caller
  end

  def test_caller_locations
    caller_locations(1, 2)
    caller_locations(1)
    caller_locations(1..2)
    caller_locations
  end

  def test_catch_throw
    catch do |tag|
      throw tag
    end

    catch("tag") do |tag|
      throw tag
    end
  end

  def test_class
    Object.new.class
  end

  def test_define_singleton_method
    define_singleton_method("_#{SecureRandom.hex(10)}") {}
    define_singleton_method(:"_#{SecureRandom.hex(10)}") {}
    define_singleton_method("_#{SecureRandom.hex(10)}", proc {})
    define_singleton_method(:"_#{SecureRandom.hex(10)}", proc {})
  end

  def test_eval
    eval "p"
    eval "p", binding, "fname", 1
  end

  def test_iterator?
    iterator?
    block_given?
  end

  def test_local_variables
    _ = x = 1
    local_variables
  end

  def test_srand
    srand
    srand(10)
    srand(10.5)
  end

  def test_not_tilde
    Object.new !~ Object.new
  end

  def test_spaceship
    Object.new <=> Object.new
  end

  def test_eqeqeq
    Object.new === Object.new
  end

  def test_eq_tilde
    Object.new =~ Object.new
  end

  def test_clone
    Object.new.clone
    Object.new.clone(freeze: false)
  end

  def test_display
    1.display
    1.display(STDERR)
  end

  def test_dup
    1.dup
  end

  def each(*args)

  end

  def test_enum_for
    enum_for :then

    enum_for :each, 1
    enum_for(:each, 1) { 2 }
  end

  def test_eql?
    Object.new.eql? 1
  end

  def test_extend
    Object.new.extend Module.new
    Object.new.extend Module.new, Module.new
  end

  def test_fork
    if Process.respond_to?(:fork)
      exit unless fork
      fork { exit }
    end
  end

  def test_freeze
    Object.new.freeze
  end

  def test_frozen?
    Object.new.frozen?
  end

  def test_hash
    Object.new.hash
  end

  def test_initialize_copy
    Object.new.instance_eval do
      initialize_copy(Object.new)
    end
  end

  def test_inspect
    Object.new.inspect
  end

  def test_instance_of?
    Object.new.instance_of? String
  end

  def test_instance_variable_defined?
    Object.new.instance_variable_defined?('@foo')
    Object.new.instance_variable_defined?(:@bar)
  end

  def test_instance_variable_get
    Object.new.instance_variable_get('@foo')
    Object.new.instance_variable_get(:@bar)
  end

  def test_instance_variable_set
    Object.new.instance_variable_set('@foo', 1)
    Object.new.instance_variable_set(:@bar, 2)
  end

  def test_instance_variables
    obj = Object.new
    obj.instance_eval do
      @foo = 1
    end
    obj.instance_variables
  end

  def test_is_a?
    Object.new.is_a? String
    Object.new.kind_of? Enumerable
  end

  def test_method
    Object.new.method(:tap)
    Object.new.method('yield_self')
  end

  def test_methods
    Object.new.methods
    Object.new.methods true
    Object.new.methods false
  end

  def test_nil?
    Object.new.nil?
  end

  def test_private_methods
    Object.new.private_methods
    Object.new.private_methods true
    Object.new.private_methods false
  end

  def test_protected_methods
    Object.new.protected_methods
    Object.new.protected_methods true
    Object.new.protected_methods false
  end

  def test_public_method
    Object.new.public_method(:tap)
    Object.new.public_method('yield_self')
  end

  def test_public_methods
    Object.new.public_methods
    Object.new.public_methods true
    Object.new.public_methods false
  end

  def test_public_send
    Object.new.public_send(:inspect)
    Object.new.public_send('inspect')
    Object.new.public_send(:public_send, :inspect)
    Object.new.public_send(:tap) { 1 }
    Object.new.public_send(:tap) { |this| this }
  end

  def test_remove_instance_variable
    obj = Object.new
    obj.instance_eval do
      @foo = 1
      @bar = 2
    end

    obj.remove_instance_variable(:@foo)
    obj.remove_instance_variable('@bar')
  end

  def test_send
    Object.new.send(:inspect)
    Object.new.send('inspect')
    Object.new.send(:public_send, :inspect)
    Object.new.send(:tap) { 1 }
    Object.new.send(:tap) { |this| this }
  end

  def test_singleton_class
    Object.new.singleton_class
  end

  def test_singleton_method
    o = Object.new
    def o.x
    end
    o.singleton_method :x
    o.singleton_method 'x'
  end

  def test_singleton_methods
    o = Object.new
    def o.x
    end
    o.singleton_methods
  end

  def test_taint
    Object.new.taint
    Object.new.untrust
  end

  def test_tainted?
    Object.new.tainted?
    Object.new.untrusted?
  end

  def test_tap
    Object.new.tap do |this|
      this
    end
  end

  def test_to_s
    Object.new.to_s
  end

  def test_untaint
    Object.new.untaint
    Object.new.trust
  end

  def test_Array
    Array(nil)
    Array('foo')
    Array(['foo'])
    Array(1..4)
    Array({foo: 1})
  end

  def test_Complex
    Complex(1.3)
    Complex(42)
    Complex(1, 2)
    Complex('42', exception: true)
  end

  def test_Float
    Float(42)
    Float(1.4)
    Float('1.4')
    Float('1.4', exception: true)
  end

  def test_Hash
    Hash(nil)
    Hash([])
    Hash({key: 1})
  end

  def test_Integer
    Integer(42)
    Integer(2.3)
    Integer('2', exception: true)
    Integer('11', 2, exception: true)
  end

  def test_Rational
    Rational(42)
    Rational(42.0, 3)
    Rational('42.0', 3, exception: true)
  end

  def test_String
    String('foo')
    String([])
    String(nil)
  end

  def test___callee__
    __callee__
  end

  def test___dir__
    __dir__
  end

  def test___method__
    __method__
  end

  def test_backtick
    `echo 1`
  end

  def test_abort
    begin
      abort
    rescue SystemExit
    end

    begin
      abort 'foo'
    rescue SystemExit
    end
  end

  def test_at_exit
    at_exit { 'foo' }
  end

  def test_autoload
    autoload 'FooBar', 'fname'
    autoload :FooBar, 'fname'
  end

  def test_autoload?
    autoload? 'FooBar'
    autoload? :FooBarBaz
  end

  def test_binding
    binding
  end

  def test_exit
    begin
      exit
    rescue SystemExit
    end

    begin
      exit 1
    rescue SystemExit
    end

    begin
      exit true
    rescue SystemExit
    end

    begin
      exit false
    rescue SystemExit
    end
  end

  def test_exit!
    # TODO
  end

  def test_fail
    # TODO
  end

  def test_format
    format 'x'
    format '%d', 1
    sprintf '%d%s', 1, 2
  end

  def test_gets
    # TODO
  end

  def test_global_variables
    global_variables
  end

  def test_load
    # TODO
  end

  def test_loop
    loop { break }
    loop
  end

  def test_open
    open(__FILE__).close
    open(__FILE__, 'r').close
    open(__FILE__, 'r', 0644).close
    open(__FILE__) do |f|
      f.read
    end
  end

  def test_print
    $stdout = StringIO.new
    print 1
    print 'a', 2
  ensure
    $stdout = STDOUT
  end

  def test_printf
    $stdout = StringIO.new
    File.open('/dev/null', 'w') do |io|
      printf io, 'a'
      printf io, '%d', 2
    end
    # TODO
    #   printf 's'
    #   printf '%d', 2
    #   printf '%d%s', 2, 1
    #   printf
  ensure
    $stdout = STDOUT
  end

  def test_proc
    proc {}
  end

  def test_lambda
    lambda {}
  end

  def test_putc
    $stdout = StringIO.new
    putc 1
    putc 'a'
  ensure
    $stdout = STDOUT
  end

  def test_puts
    $stdout = StringIO.new
    puts 1
    puts Object.new
  ensure
    $stdout = STDOUT
  end

  def test_p
    $stdout = StringIO.new
    p 1
    p 'a', 2
  ensure
    $stdout = STDOUT
  end

  def test_rand
    rand
    rand(10)
    rand(1..10)
    rand(1.0..10.0)
  end

  def test_readline
    # TODO
  end

  def test_readlines
    # TODO
  end

  def test_require
    # TODO
  end

  def test_require_relative
    # TODO
  end

  def test_select
    # TODO
  end

  def test_sleep
    # TODO
    #   sleep

    sleep 0.01
  end

  def test_syscall
    # TODO
  end

  def test_test
    test ?r, __FILE__
    test ?r.ord, __FILE__
    test ?s, __FILE__

    File.open(__FILE__) do |f|
      test ?r, f
      test ?=, f, f
    end
  end

  def test_warn
    $stderr = StringIO.new
    warn
    warn 'foo'
    warn 'foo', 'bar'
    warn 'foo', uplevel: 1
  ensure
    $stderr = STDERR
  end

  def test_exec
    # TODO
  end

  def test_system
    # TODO
  end
end
