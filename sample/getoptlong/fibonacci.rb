require 'getoptlong'

options = GetoptLong.new(
  ['--number', '-n', GetoptLong::REQUIRED_ARGUMENT],
  ['--verbose', '-v', GetoptLong::OPTIONAL_ARGUMENT],
  ['--help', '-h', GetoptLong::NO_ARGUMENT]
)

def help(status = 0)
  puts <<~HELP
    Usage:

      -n n, --number n:
        Compute Fibonacci number for n.
      -v [boolean], --verbose [boolean]:
        Show intermediate results; default is 'false'.
      -h, --help:
        Show this help.
  HELP
  exit(status)
end

def print_fibonacci (number)
  return 0 if number == 0
  return 1 if number == 1 or number == 2
  i = 0
  j = 1
  (2..number).each do
    k = i + j
    i = j
    j = k
    puts j if @verbose
  end
  puts j unless @verbose
end

options.each do |option, argument|
  case option
  when '--number'
    @number = argument.to_i
  when '--verbose'
    @verbose = if argument.empty?
      true
    elsif argument.match(/true/i)
      true
    elsif argument.match(/false/i)
      false
    else
      puts '--verbose argument must be true or false'
      help(255)
    end
  when '--help'
    help
  end
end

unless @number
  puts 'Option --number is required.'
  help(255)
end

print_fibonacci(@number)
