require 'optparse'
parser = OptionParser.new
parser.on('-xXXX', ['foo', 'bar'], 'Values for required argument' ) do |value|
  p ['-x', value]
end
parser.on('-y [YYY]', ['baz', 'bat'], 'Values for optional argument') do |value|
  p ['-y', value]
end
parser.parse!
