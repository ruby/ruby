def test(a1, *a2)
 while 1
  switch gets()
  case nil
    break
  case /^-$/
    print("-\n")
    return
  case /^-help/
    print("-help\n")
    break
  end
 end
 print(a1, a2, "\n")
end

print($ARGV, "\n")
print("in: ")
test(1)
print("end\n")
