require 'getoptlong'

options = GetoptLong.new(
  ['--xxx', '-x', GetoptLong::REQUIRED_ARGUMENT],
  ['--yyy', '-y', GetoptLong::OPTIONAL_ARGUMENT],
  ['--zzz', '-z',GetoptLong::NO_ARGUMENT]
)
puts "Original ARGV: #{ARGV}"
options.each do |option, argument|
  p [option, argument]
end
puts "Remaining ARGV: #{ARGV}"
