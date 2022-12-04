require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx', '=XXX', 'Required argument') do |value|
  p ['--xxx', value]
end
parser.parse!
