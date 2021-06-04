class MockObject
  def initialize(name, options = {})
    @name = name
    @null = options[:null_object]
  end

  def method_missing(sym, *args, &block)
    @null ? self : super
  end
  private :method_missing
end

class NumericMockObject < Numeric
  def initialize(name, options = {})
    @name = name
    @null = options[:null_object]
  end

  def method_missing(sym, *args, &block)
    @null ? self : super
  end

  def singleton_method_added(val)
  end
end

class MockIntObject
  def initialize(val)
    @value = val
    @calls = 0

    key = [self, :to_int]

    Mock.objects[key] = self
    Mock.mocks[key] << self
  end

  attr_reader :calls

  def to_int
    @calls += 1
    @value.to_int
  end

  def count
    [:at_least, 1]
  end
end

class MockProxy
  attr_reader :raising, :yielding

  def initialize(type = nil)
    @multiple_returns = nil
    @returning = nil
    @raising   = nil
    @yielding  = []
    @arguments = :any_args
    @type      = type || :mock
  end

  def mock?
    @type == :mock
  end

  def stub?
    @type == :stub
  end

  def count
    @count ||= mock? ? [:exactly, 1] : [:any_number_of_times, 0]
  end

  def arguments
    @arguments
  end

  def returning
    if @multiple_returns
      if @returning.size == 1
        @multiple_returns = false
        return @returning = @returning.shift
      end
      return @returning.shift
    end
    @returning
  end

  def times
    self
  end

  def calls
    @calls ||= 0
  end

  def called
    @calls = calls + 1
  end

  def exactly(n)
    @count = [:exactly, n_times(n)]
    self
  end

  def at_least(n)
    @count = [:at_least, n_times(n)]
    self
  end

  def at_most(n)
    @count = [:at_most, n_times(n)]
    self
  end

  def once
    exactly 1
  end

  def twice
    exactly 2
  end

  def any_number_of_times
    @count = [:any_number_of_times, 0]
    self
  end

  def with(*args)
    raise ArgumentError, "you must specify the expected arguments" if args.empty?
    if args.length == 1
      @arguments = args.first
    else
      @arguments = args
    end
    self
  end

  def and_return(*args)
    case args.size
    when 0
      @returning = nil
    when 1
      @returning = args[0]
    else
      @multiple_returns = true
      @returning = args
      count[1] = args.size if count[1] < args.size
    end
    self
  end

  def and_raise(exception)
    if exception.kind_of? String
      @raising = RuntimeError.new exception
    else
      @raising = exception
    end
  end

  def raising?
    @raising != nil
  end

  def and_yield(*args)
    @yielding << args
    self
  end

  def yielding?
    !@yielding.empty?
  end

  private

  def n_times(n)
    case n
    when :once
      1
    when :twice
      2
    else
      Integer n
    end
  end
end
