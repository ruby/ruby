grep_data = (1..10).to_a * 1000
N = 100
enum = grep_data.lazy.grep_v(->(i){i > 5}).grep_v(->(i){i > 5})
N.times {enum.each {}}
