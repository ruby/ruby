def freq(s)
    if s.empty?
        return ""
    end
    map = Hash.new
    for i in 0..s.length - 1 do
        if map.has_key?(s[i])
            map[s[i]] = map[s[i]] + 1
        else
            map.store(s[i], 1)
        end
    end
    keys = map.keys
    frequent = s[0]
    for i in keys do
        if (map[i] > map[frequent])
            frequent = i
        end
    end
    return frequent
end