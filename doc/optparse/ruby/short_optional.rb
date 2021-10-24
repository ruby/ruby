require 'optparse'
parser = OptionParser.new
parser.on('-x [XXX]', 'Short name with optional argument') do |value|
  p ['-x', value]
end
parser.parse!
