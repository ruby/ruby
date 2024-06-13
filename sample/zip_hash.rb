def zipHash(arr1, arr2)
    if arr1.size != arr2.size
        return nil
    end
    map = Hash.new
    for i in 0..arr1.size - 1 do
        map.store(arr1[i], arr2[i])
    end
    return map
end