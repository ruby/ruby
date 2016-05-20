s = "x"*10 + "y"
i = 0
while i < 1_000_000
  /z/.match?(s)
  i += 1
end
