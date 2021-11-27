require 'optparse'
parser = OptionParser.new
parser.on('--xxx') do |value|
  p ['--xxx', value]
end
parser.on('--yyy YYY') do |value|
  p ['--yyy', value]
end
parser.on('--zzz [ZZZ]') do |value|
  p ['--zzz', value]
end
ret = parser.parse!
puts "Returned: #{ret} (#{ret.class})"
