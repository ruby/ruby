require 'optparse'
parser = OptionParser.new
parser.on('-xXXX', 'Short name with required argument') do |value|
  p ['-x', value]
end
parser.parse!
