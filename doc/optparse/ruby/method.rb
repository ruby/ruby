require 'optparse'
parser = OptionParser.new
def xxx_handler(value)
  p ['Handler method for -xxx called with value:', value]
end
parser.on('--xxx', 'Option with no argument', method(:xxx_handler))
def yyy_handler(value)
  p ['Handler method for -yyy called with value:', value]
end
parser.on('--yyy YYY', 'Option with required argument', method(:yyy_handler))
parser.parse!
