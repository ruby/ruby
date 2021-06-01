require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx', :REQUIRED, 'Required argument') do |value|
  p ['--xxx', value]
end
parser.parse!
