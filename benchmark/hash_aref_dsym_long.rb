# [ruby-core:70129] [Bug #11396]
collection_size = 200000
sample_size = 10000

values = (1..collection_size).to_a.map do |x|
  "THIS IS A LONGER STRING THAT IS ALSO UNIQUE #{x}"
end

symbol_hash = {}

values.each do |x|
  symbol_hash[x.to_sym] = 1
end

# use the same samples each time to minimize deviations
rng = Random.new(0)
symbol_sample_array = values.sample(sample_size, random: rng).map(&:to_sym)

3000.times do
  symbol_sample_array.each { |x| symbol_hash[x] }
end
