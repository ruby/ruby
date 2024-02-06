def freq(s)
  if s.empty?
    return ""
  end
  map = Hash.new(0)
  s.each_char do |i|
    map[s[i]] += 1
  end
  map.max_by {|_, i| i}.first
end