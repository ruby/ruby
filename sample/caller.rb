def test
  for i in 1..2
    for j in 1..5
      print(j, ": ", caller(j).join(':'), "\n")
    end
  end
end

def test2
  print(1, ": ", caller(1).join(':'), "\n")
  test()
end

test2()
caller()
