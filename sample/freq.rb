# word occurrence listing
# usege: ruby freq.rb file..
freq = {}
while gets
  while sub!(/\w+/, '')
    word = $&
    freq[word] +=1
  end
end

for word in freq.keys.sort
  printf("%s -- %d\n", word, freq[word])
end
