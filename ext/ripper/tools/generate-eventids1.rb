#
# generate-eventids1.rb
#

ids = ARGF.map {|s| s.strip }

ids.each do |id|
  puts "static ID ripper_id_#{id};"
end

puts
puts 'static void'
puts 'ripper_init_eventids1()'
puts '{'
ids.each do |id|
  puts %Q[    ripper_id_#{id} = rb_intern("on__#{id}");]
end
puts '}'
