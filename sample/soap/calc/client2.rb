require 'soap/rpc/driver'

server = ARGV.shift || 'http://localhost:7000/'
# server = 'http://localhost:8808/server2.cgi'

var = SOAP::RPC::Driver.new( server, 'http://tempuri.org/calcService' )
var.add_method( 'set', 'newValue' )
var.add_method( 'get' )
var.add_method_as( '+', 'add', 'rhs' )
var.add_method_as( '-', 'sub', 'rhs' )
var.add_method_as( '*', 'multi', 'rhs' )
var.add_method_as( '/', 'div', 'rhs' )

puts 'var.set( 1 )'
puts '# Bare in mind that another client set another value to this service.'
puts '# This is only a sample for proof of concept.'
var.set( 1 )
puts 'var + 2	# => 1 + 2 = 3'
puts var + 2
puts 'var - 2.2	# => 1 - 2.2 = -1.2'
puts var - 2.2
puts 'var * 2.2	# => 1 * 2.2 = 2.2'
puts var * 2.2
puts 'var / 2	# => 1 / 2 = 0'
puts var / 2
puts 'var / 2.0	# => 1 / 2.0 = 0.5'
puts var / 2.0
puts 'var / 0	# => 1 / 0 => ZeroDivisionError'
puts var / 0
