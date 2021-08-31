require 'optparse'
parser = OptionParser.new
parser.on('-x', 'One short name') do |value|
  p ['-x', value]
end
parser.on('-1', '-%', 'Two short names (aliases)') do |value|
  p ['-1 or -%', value]
end
parser.parse!
