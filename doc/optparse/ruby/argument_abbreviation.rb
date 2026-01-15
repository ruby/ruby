require 'optparse'
parser = OptionParser.new
parser.on('-x', '--xxx=VALUE', %w[ABC def], 'Argument abbreviations') do |value|
  p ['--xxx', value]
end
parser.on('-y', '--yyy=VALUE', {"abc"=>"XYZ", def: "FOO"}, 'Argument abbreviations') do |value|
  p ['--yyy', value]
end
parser.parse!
