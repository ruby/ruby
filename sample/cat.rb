while gets()
  if $. == 1 ... ~ /^\*/; print("--") end
  printf("%5d: %s", $., $_)
end
