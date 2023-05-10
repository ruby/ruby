def is_palindrome(n)
  s = n.to_s
  (s.size / 2).times.all? {|i| s[i] == s[-1-i]}
end