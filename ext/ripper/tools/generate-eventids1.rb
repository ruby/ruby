# $Id$

ids = File.readlines(ARGV[0]).map {|s| s.split[0] }

ids.each do |id|
  puts "static ID ripper_id_#{id};"
end

puts
puts 'static void'
puts 'ripper_init_eventids1()'
puts '{'
ids.each do |id|
  puts %Q[    ripper_id_#{id} = rb_intern("on_#{id}");]
end
puts '}'
