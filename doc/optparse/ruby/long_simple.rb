require 'optparse'
parser = OptionParser.new
parser.on('--xxx', 'One long name') do |value|
  p ['--xxx', value]
end
parser.on('--y1%', '--z2#', 'Two long names (aliases)') do |value|
  p ['--y1% or --z2#', value]
end
parser.parse!
