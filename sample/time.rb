#! /usr/local/bin/ruby
cmd = ARGV.join(" ")
b = Time.now
system(cmd)
e = Time.now
ut, st, cut, cst = Time.times.to_a
total = (e - b).to_f
printf STDERR, "%11.1f real %11.1f user %11.1f sys\n", total, cut, cst
