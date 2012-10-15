def rec n
  if n > 0
    rec n-1
  else
    raise
  end
end

i = 0
while i<6_000_000 # benchmark loop 2
  i += 1

  begin
    rec 10
  rescue
    # ignore
  end
end
