def hashToArray(hash)
    arr = Array.new
    for i in hash.keys do
        arr.push(Array[i, hash[i]])
    end
    return arr
end