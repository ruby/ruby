# word occurrence listing
# usege: ruby occur.rb file..
freq = {}
while gets()
  for word in $_.split(/\W+/)
    freq[word] +=1
  end
end

for word in freq.keys.sort
  printf("%s -- %d\n", word, freq[word])
end
