def nthmax(n, a)
    if n > a.size - 1
        return nil
    end
    a = a.sort { |a, b| b <=> a }
    return a[n]
end