require 'optparse'
parser = OptionParser.new
parser.on('--xxx') do |value|
  p ['-xxx', value]
end
parser.on('--y1%', '--z2#') do |value|
  p ['--y1% or --z2#', value]
end
parser.parse!
