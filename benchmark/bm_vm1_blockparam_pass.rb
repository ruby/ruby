def bp_yield
  yield
end

def bp_pass &b
  bp_yield &b
end

i = 0
while i<30_000_000 # while loop 1
  i += 1
  bp_pass{}
end
