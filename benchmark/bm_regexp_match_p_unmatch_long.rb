s = "x"*100000 + "y"
i = 0
while i < 100_000
  /z/.match?(s)
  i += 1
end
