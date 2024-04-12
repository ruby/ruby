# frozen_string_literal: true
frozen = "test".frozen?
interned = "test".equal?("test")
puts "frozen:#{frozen} interned:#{interned}"
