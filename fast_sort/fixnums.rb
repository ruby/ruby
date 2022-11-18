#!/bin/ruby

srand 0
r = $*[0] == 'sorted' ? (-5_000_000...5_000_000).to_a :
                        (Array.new 1e7.to_i do rand -2 ** 40...2 ** 40 end)

puts

5.times do

    a = r.clone
    t = Time.now
    a.sort!
    puts "\tRun ##{_1 + 1}: %.3f s" % [Time.now - t]

end

puts; exit unless $*[0]

p (r.sort { _1 <=> _2 }) == (r.sort)

puts
