h = {}
nums = (1..26).to_a
nums.each { |i| h[i] = i }
800_000.times { nums.each { |s| h[s] } }
