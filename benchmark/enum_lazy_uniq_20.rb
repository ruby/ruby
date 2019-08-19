uniq_data = (1..10_000).to_a
N = 100
enum = uniq_data.lazy.uniq {|i| i % 2000}.uniq {|i| i % 2000}
N.times {enum.each {}}
