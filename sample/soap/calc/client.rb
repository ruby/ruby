require 'soap/rpc/driver'

server = ARGV.shift || 'http://localhost:7000/'
# server = 'http://localhost:8808/server.cgi'

calc = SOAP::RPC::Driver.new(server, 'http://tempuri.org/calcService')
#calc.wiredump_dev = STDERR
calc.add_method('add', 'lhs', 'rhs')
calc.add_method('sub', 'lhs', 'rhs')
calc.add_method('multi', 'lhs', 'rhs')
calc.add_method('div', 'lhs', 'rhs')

puts 'add: 1 + 2	# => 3'
puts calc.add(1, 2)
puts 'sub: 1.1 - 2.2	# => -1.1'
puts calc.sub(1.1, 2.2)
puts 'multi: 1.1 * 2.2	# => 2.42'
puts calc.multi(1.1, 2.2)
puts 'div: 5 / 2	# => 2'
puts calc.div(5, 2)
puts 'div: 5.0 / 2	# => 2.5'
puts calc.div(5.0, 2)
puts 'div: 1.1 / 0	# => Infinity'
puts calc.div(1.1, 0)
puts 'div: 1 / 0	# => ZeroDivisionError'
puts calc.div(1, 0)
