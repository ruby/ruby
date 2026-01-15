require 'optparse'
require 'set'

# Number of iterations to test
num_iters = 10_000

# Parse the command-line options
OptionParser.new do |opts|
  opts.on("--num-iters=N") do |n|
    num_iters = n.to_i
  end
end.parse!

# Format large numbers with comma separators for readability
def format_number(pad, number)
  s = number.to_s
  i = s.index('.') || s.size
  s.insert(i -= 3, ',') while i > 3
  s.rjust(pad, ' ')
end

# Wrap an integer to pass as argument
# We use this so we can have some object arguments
class IntWrapper
  def initialize(v)
    # Force the object to have a random shape
    if rand() < 50
      @v0 = 1
    end
    if rand() < 50
      @v1 = 1
    end
    if rand() < 50
      @v2 = 1
    end
    if rand() < 50
      @v3 = 1
    end
    if rand() < 50
      @v4 = 1
    end
    if rand() < 50
      @v5 = 1
    end
    if rand() < 50
      @v6 = 1
    end

    @value = v
  end

  attr_reader :value
end

# Generate a random argument value, integer or string or object
def sample_arg()
  c = ['int', 'string', 'object'].sample()

  if c == 'int'
    return rand(0...100)
  end

  if c == 'string'
    return 'f' * rand(0...100)
  end

  if c == 'object'
    return IntWrapper.new(rand(0...100))
  end

  raise "should not get here"
end

# Evaluate the value of an argument with respect to the checksum
def arg_val(arg)
  if arg.kind_of? Integer
    return arg
  end

  if arg.kind_of? String
    return arg.length
  end

  if arg.kind_of? Object
    return arg.value
  end

  raise "unknown arg type"
end

# List of parameters/arguments for a method
class ParamList
  def initialize()
    self.sample_params()
    self.sample_args()
  end

  # Sample/generate a random set of parameters for a method
  def sample_params()
    # Choose how many positional arguments to use, and how many are optional
    num_pargs = rand(10)
    @opt_parg_idx = rand(num_pargs)
    @num_opt_pargs = rand(num_pargs + 1 - @opt_parg_idx)
    @num_pargs_req = num_pargs - @num_opt_pargs
    @pargs = (0...num_pargs).map do |i|
      {
        :name => "p#{i}",
        :optional => (i >= @opt_parg_idx && i < @opt_parg_idx + @num_opt_pargs)
      }
    end

    # Choose how many kwargs to use, and how many are optional
    num_kwargs = rand(10)
    @kwargs = (0...num_kwargs).map do |i|
      {
        :name => "k#{i}",
        :optional => rand() < 0.5
      }
    end

    # Choose whether to have rest parameters or not
    @has_rest = @num_opt_pargs == 0 && rand() < 0.5
    @has_kwrest = rand() < 0.25

    # Choose whether to have a named block parameter or not
    @has_block_param = rand() < 0.25
  end

  # Sample/generate a random set of arguments corresponding to the parameters
  def sample_args()
    # Choose how many positional args to pass
    num_pargs_passed = rand(@num_pargs_req..@pargs.size)

    # How many optional arguments will be filled
    opt_pargs_filled = num_pargs_passed - @num_pargs_req

    @pargs.each_with_index do |parg, i|
      if parg[:optional]
        parg[:default] = rand(100)
      end

      if !parg[:optional] || i < @opt_parg_idx + opt_pargs_filled
        parg[:argval] = rand(100)
      end
    end

    @kwargs.each_with_index do |kwarg, i|
      if kwarg[:optional]
        kwarg[:default] = rand(100)
      end

      if !kwarg[:optional] || rand() < 0.5
        kwarg[:argval] = rand(100)
      end
    end

    # Randomly pass a block or not
    @block_arg = nil
    if rand() < 0.5
      @block_arg = rand(100)
    end
  end

  # Compute the expected checksum of arguments ahead of time
  def compute_checksum()
    checksum = 0

    @pargs.each_with_index do |arg, i|
      value = (arg.key? :argval)? arg[:argval]:arg[:default]
      checksum += (i+1) * arg_val(value)
    end

    @kwargs.each_with_index do |arg, i|
      value = (arg.key? :argval)? arg[:argval]:arg[:default]
      checksum += (i+1) * arg_val(value)
    end

    if @block_arg
      if @has_block_param
        checksum += arg_val(@block_arg)
      end

      checksum += arg_val(@block_arg)
    end

    checksum
  end

  # Generate code for the method signature and method body
  def gen_method_str()
    m_str = "def m("

    @pargs.each do |arg|
      if !m_str.end_with?("(")
        m_str += ", "
      end

      m_str += arg[:name]

      # If this has a default value
      if arg[:optional]
        m_str += " = #{arg[:default]}"
      end
    end

    if @has_rest
      if !m_str.end_with?("(")
        m_str += ", "
      end
      m_str += "*rest"
    end

    @kwargs.each do |arg|
      if !m_str.end_with?("(")
        m_str += ", "
      end

      m_str += "#{arg[:name]}:"

      # If this has a default value
      if arg[:optional]
        m_str += " #{arg[:default]}"
      end
    end

    if @has_kwrest
      if !m_str.end_with?("(")
        m_str += ", "
      end
      m_str += "**kwrest"
    end

    if @has_block_param
      if !m_str.end_with?("(")
        m_str += ", "
      end

      m_str += "&block"
    end

    m_str += ")\n"

    # Add some useless locals
    rand(0...16).times do |i|
      m_str += "local#{i} = #{i}\n"
    end

    # Add some useless if statements
    @pargs.each_with_index do |arg, i|
      if rand() < 50
        m_str += "if #{arg[:name]} > 4; end\n"
      end
    end

    m_str += "checksum = 0\n"

    @pargs.each_with_index do |arg, i|
      m_str += "checksum += #{i+1} * arg_val(#{arg[:name]})\n"
    end

    @kwargs.each_with_index do |arg, i|
      m_str += "checksum += #{i+1} * arg_val(#{arg[:name]})\n"
    end

    if @has_block_param
      m_str += "if block; r = block.call; checksum += arg_val(r); end\n"
    end

    m_str += "if block_given?; r = yield; checksum += arg_val(r); end\n"

    if @has_rest
      m_str += "raise 'rest is not array' unless rest.kind_of?(Array)\n"
      m_str += "raise 'rest size not integer' unless rest.size.kind_of?(Integer)\n"
    end

    if @has_kwrest
      m_str += "raise 'kwrest is not a hash' unless kwrest.kind_of?(Hash)\n"
      m_str += "raise 'kwrest size not integer' unless kwrest.size.kind_of?(Integer)\n"
    end

    m_str += "checksum\n"
    m_str += "end"

    m_str
  end

  # Generate code to call into the method and pass the arguments
  def gen_call_str()
    c_str = "m("

    @pargs.each_with_index do |arg, i|
      if !arg.key? :argval
        next
      end

      if !c_str.end_with?("(")
        c_str += ", "
      end

      c_str += "#{arg[:argval]}"
    end

    @kwargs.each_with_index do |arg, i|
      if !arg.key? :argval
        next
      end

      if !c_str.end_with?("(")
        c_str += ", "
      end

      c_str += "#{arg[:name]}: #{arg[:argval]}"
    end

    c_str += ")"

    # Randomly pass a block or not
    if @block_arg
      c_str += " { #{@block_arg} }"
    end

    c_str
  end
end

iseqs_compiled_start = RubyVM::YJIT.runtime_stats[:compiled_iseq_entry]
start_time = Time.now.to_f

num_iters.times do |i|
  puts "Iteration #{i}"

  lst = ParamList.new()
  m_str = lst.gen_method_str()
  c_str = lst.gen_call_str()
  checksum = lst.compute_checksum()

  f = Object.new

  # Define the method on f
  puts "Defining"
  p m_str
  f.instance_eval(m_str)
  #puts RubyVM::InstructionSequence.disasm(f.method(:m))
  #exit 0

  puts "Calling"
  c_str = "f.#{c_str}"
  p c_str
  r = eval(c_str)
  puts "checksum=#{r}"

  if r != checksum
    raise "return value #{r} doesn't match checksum #{checksum}"
  end

  puts ""
end

# Make sure that YJIT actually compiled the tests we ran
# Should be run with --yjit-call-threshold=1
iseqs_compiled_end = RubyVM::YJIT.runtime_stats[:compiled_iseq_entry]
if iseqs_compiled_end - iseqs_compiled_start < num_iters
  raise "YJIT did not compile enough ISEQs"
end

puts "Code region size: #{ format_number(0, RubyVM::YJIT.runtime_stats[:code_region_size]) }"

end_time = Time.now.to_f
itrs_per_sec = num_iters / (end_time - start_time)
itrs_per_hour = 3600 * itrs_per_sec
puts "#{'%.1f' % itrs_per_sec} iterations/s"
puts "#{format_number(0, itrs_per_hour.round)} iterations/hour"
