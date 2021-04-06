require 'optparse'
parser = OptionParser.new
parser.on('-x') do |value|
  p ['x', value]
end
parser.on('-1', '-%') do |value|
  p ['-1 or -%', value]
end
parser.parse!
