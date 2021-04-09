require 'optparse'
parser = OptionParser.new
parser.on('--xxx XXX', /foo/i, 'Matched values') do |value|
  p ['--xxx', value]
end
parser.parse!
