def test(a1, *a2)
 while 1
  case gets()
  when nil
    break
  when /^-$/
    print("-\n")
    return
  when /^-help/
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
