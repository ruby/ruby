# sieve of Eratosthenes
sieve = []
if ! max = $ARGV.shift; max = 100; end
max = max.to_i

print "1"
for i in 2 .. max 
  protect
    for d in sieve
      fail if i % d == 0
    end
    print ", "
    print i
    sieve.push(i)
  resque
  end
end
print "\n"
