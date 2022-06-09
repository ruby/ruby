require 'getoptlong'

options = GetoptLong.new(
  ['--xxx', GetoptLong::REQUIRED_ARGUMENT],
  ['--yyy', GetoptLong::OPTIONAL_ARGUMENT],
  ['--zzz', GetoptLong::NO_ARGUMENT]
)
options.ordering = GetoptLong::RETURN_IN_ORDER
puts "Original ARGV: #{ARGV}"
options.each do |option, argument|
  p [option, argument]
end
puts "Remaining ARGV: #{ARGV}"
