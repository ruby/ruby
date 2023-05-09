def isPalindrome(n)
    s = n.to_s
    length = s.size
    head = 0
    tail = length - 1
    while head <= tail do
        if s[head] != s[tail]
            return false
        end
        head += 1
        tail -= 1
    end
    return true
end