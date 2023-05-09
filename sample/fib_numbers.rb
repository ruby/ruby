def fib(n)
    fib_arr = Array.new
    for i in 1..n do
        if i == 1
            fib_arr.push(0)
        elsif i == 2
            fib_arr.push(1)
        else
            fib_arr.push(fib_arr[i - 3] + fib_arr[i - 2])
        end
    end
    return fib_arr
end