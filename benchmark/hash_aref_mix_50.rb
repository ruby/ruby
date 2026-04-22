h = {}
present = Array.new(1024) { |i| "k#{i}".freeze }
present.each { |k| h[k] = k }
missing = Array.new(1024) { |i| "miss#{i}".freeze }
mixed = Array.new(2048) { |i| i.even? ? present[i / 2] : missing[i / 2] }.freeze
5_000.times { mixed.each { |k| h[k] } }
