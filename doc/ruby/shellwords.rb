require 'optparse/shellwords'
parser = OptionParser.new
parser.on('--shellwords=SHELLWORDS', Shellwords) do |value|
  p [value, value.class]
end
parser.parse!
