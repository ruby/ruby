freq = {}
while gets()
  for word in $_.split(/\W+/)
    protect
      freq[word] = freq[word] + 1
    resque
      freq[word] = 1
    end
  end
end

for word in freq.keys.sort
  printf("%s -- %d\n", word, freq[word])
end
