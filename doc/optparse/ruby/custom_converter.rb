require 'optparse/date'
parser = OptionParser.new
parser.accept(Complex) do |value|
  value.to_c
end
parser.on('--complex COMPLEX', Complex) do |value|
  p [value, value.class]
end
parser.parse!
