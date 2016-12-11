s = "x"*100000 + "y"
i = 0
while i < 100_000
  /y/.match?(s)
  i += 1
end
