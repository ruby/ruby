# cat -n & `...' operator test
while gets()
  if 1 ... /^\*/; print("--") end
  printf("%5d: %s", $., $_)
end
