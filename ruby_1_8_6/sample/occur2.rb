# word occurrence listing
# usege: ruby occur2.rb file..
freq = {}
while gets()
  for word in split(/\W+/)
    begin
      freq[word] += 1
    rescue NameError
      freq[word] = 1
    end
  end
end

for word in freq.keys.sort
  printf("%s -- %d\n", word, freq[word])
end
