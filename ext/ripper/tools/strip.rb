# frozen_string_literal: false
last_is_void = false
ARGF.each do |line|
  case line
  when /\A\s*\z/, /\A\#/
    puts unless last_is_void
    last_is_void = true
  else
    print line
    last_is_void = false
  end
end
