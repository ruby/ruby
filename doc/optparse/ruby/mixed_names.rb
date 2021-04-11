require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx', 'Short and long, no argument') do |value|
  p ['--xxx', value]
end
parser.on('-yYYY', '--yyy', 'Short and long, required argument') do |value|
  p ['--yyy', value]
end
parser.on('-z [ZZZ]', '--zzz', 'Short and long, optional argument') do |value|
  p ['--zzz', value]
end
parser.parse!
