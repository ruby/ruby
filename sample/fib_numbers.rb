def fib_numbers(n)
  case
  when n < 1
    return []
  when n == 1
    return [0]
  end

  fib_arr = [0, 1]
  3.upto(n) do
    fib_arr.push(fib_arr[-2] + fib_arr[-1])
  end
  return fib_arr
end