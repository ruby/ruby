# frozen_string_literal: false
frozen = "test".frozen?
interned = "test".equal?("test")
puts "frozen:#{frozen} interned:#{interned}"
