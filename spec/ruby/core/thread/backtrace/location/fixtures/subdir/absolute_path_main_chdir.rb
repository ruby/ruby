puts __FILE__
puts __dir__
Dir.chdir __dir__

# Check __dir__ is still correct after chdir
puts __dir__

puts caller_locations(0)[0].absolute_path

# require_relative also needs to know the absolute path of the current file so we test it here too
require_relative 'sibling'
