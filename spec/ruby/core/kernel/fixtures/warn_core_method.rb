raise 'should be run without RubyGems' if defined?(Gem)

def deprecated(n=1)
  # puts nil, caller(0), nil
  warn "use X instead", uplevel: n
end

1.times do # to test with a non-empty stack above the reported locations
  deprecated
  tap(&:deprecated)
  tap { deprecated(2) }
  # eval sources with a <internal: file are also ignored
  eval "tap(&:deprecated)", nil, "<internal:should-be-skipped-by-warn-uplevel>"
end
