require 'optparse'
require 'set'

# Number of iterations to test
num_iters = 10_000

# Parse the command-line options
OptionParser.new do |opts|
  opts.on("--num_iters=N") do |n|
    num_iters = n.to_i
  end
end.parse!

def gen_random_method()
  # Choose how many positional arguments to use, and how many are optional
  num_pargs = rand(10)
  opt_parg_idx = rand(num_pargs)
  num_opt_pargs = rand( num_pargs + 1 - opt_parg_idx)
  pargs = []
  num_pargs.times { |i| pargs.push("p#{i}") }
  opt_pargs = pargs[opt_parg_idx...opt_parg_idx + num_opt_pargs]

  # Choose how many kwargs to use, and how many are optional
  num_kwargs = rand(10)
  num_opt_kwargs = rand(num_kwargs + 1)
  kwargs = []
  num_kwargs.times { |i| kwargs.push("k#{i}") }
  opt_kwargs = kwargs.sample(num_opt_kwargs)

  # Choose whether to have a block argument and splats or not
  block_arg = rand() < 0.5
  has_rest = num_opt_pargs == 0 && rand() < 0.5
  has_kwrest = rand() < 0.5

  # Generate a method definitions
  m_str = "def m("

  pargs.each_with_index do |name, i|
    if !m_str.end_with?("(")
      m_str += ", "
    end
    m_str += "#{name}"

    # If this has a default value
    if opt_pargs.include?(name)
      m_str += " = #{i}"
    end
  end

  if has_rest
    if !m_str.end_with?("(")
      m_str += ", "
    end
    m_str += "*rest"
  end

  kwargs.each_with_index do |name, i|
    if !m_str.end_with?("(")
      m_str += ", "
    end
    m_str += "#{name}:"

    # If this has a default value
    if opt_kwargs.include?(name)
      m_str += " #{i}"
    end
  end

  if has_kwrest
    if !m_str.end_with?("(")
      m_str += ", "
    end
    m_str += "**kwrest"
  end

  if block_arg
    if !m_str.end_with?("(")
      m_str += ", "
    end
    m_str += "&block"
  end

  m_str += ")\n"
  if block_arg
    m_str += "if block; block.call; end\n"
  end
  m_str += "if block_given?; yield; end\n"
  m_str += "777\n"
  m_str += "end"

  # Generate a random call to the method
  c_str = "m("

  pargs.each_with_index do |name, i|
    if !c_str.end_with?("(")
      c_str += ", "
    end

    c_str += "#{i}"

    # TODO: don't always pass optional positional args
  end

  kwargs.each_with_index do |name, i|
    # Don't always pass optional kwargs
    if opt_kwargs.include?(name) && rand() < 0.5
      next
    end

    if !c_str.end_with?("(")
      c_str += ", "
    end

    c_str += "#{name}: #{i}"
  end

  c_str += ")"

  # Randomly pass a block or not
  if rand() < 0.5
    c_str += " { 1 }"
  end

  [m_str, c_str]
end

iseqs_compiled_start = RubyVM::YJIT.runtime_stats[:compiled_iseq_entry]

num_iters.times do |i|
  puts "Iteration #{i}"

  m_str, c_str = gen_random_method()

  eval("class Foo; end")

  f = Foo.new()

  # Define the method on f
  puts "Defining"
  p m_str
  f.instance_eval(m_str)

  puts "Calling"
  c_str = "f.#{c_str}"
  p c_str
  r = eval(c_str)
  p r

  if r != 777
    raise "incorrect return value"
  end

  puts ""
end

iseqs_compiled_end = RubyVM::YJIT.runtime_stats[:compiled_iseq_entry]
if iseqs_compiled_end - iseqs_compiled_start < num_iters
  raise "YJIT did not compile enough ISEQs"
end
