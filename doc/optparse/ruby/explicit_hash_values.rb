require 'optparse'
parser = OptionParser.new
parser.on('-xXXX', {foo: 0, bar: 1}, 'Values for required argument' ) do |value|
  p ['-x', value]
end
parser.on('-y [YYY]', {baz: 2, bat: 3}, 'Values for optional argument') do |value|
  p ['-y', value]
end
parser.parse!
