i = 0
module M
end
$VERBOSE = nil
while i<6_000_000 # benchmark loop 2
  i += 1
  M.const_set(:X, Module.new)
end
