# word occurrence listing
# usege: ruby occur.rb file..
freq = Hash.new(0)
while gets()
  for word in $_.split(/\W+/)
    freq[word] += 1
  end
end

for word in freq.keys.sort!
  print word, " -- ", freq[word], "\n"
end
