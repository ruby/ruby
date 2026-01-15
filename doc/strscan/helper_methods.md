## Helper Methods

These helper methods display values returned by scanner's methods.

### `put_situation(scanner)`

Display scanner's situation:

- Byte position (`#pos`).
- Character position (`#charpos`)
- Target string (`#rest`) and size (`#rest_size`).

```rb
scanner = StringScanner.new('foobarbaz')
scanner.scan(/foo/)
put_situation(scanner)
# Situation:
#   pos:       3
#   charpos:   3
#   rest:      "barbaz"
#   rest_size: 6
```

### `put_match_values(scanner)`

Display the scanner's match values:

```rb
scanner = StringScanner.new('Fri Dec 12 1975 14:39')
pattern = /(?<wday>\w+) (?<month>\w+) (?<day>\d+) /
scanner.match?(pattern)
put_match_values(scanner)
# Basic match values:
#   matched?:       true
#   matched_size:   11
#   pre_match:      ""
#   matched  :      "Fri Dec 12 "
#   post_match:     "1975 14:39"
# Captured match values:
#   size:           4
#   captures:       ["Fri", "Dec", "12"]
#   named_captures: {"wday"=>"Fri", "month"=>"Dec", "day"=>"12"}
#   values_at:      ["Fri Dec 12 ", "Fri", "Dec", "12", nil]
#   []:
#     [0]:          "Fri Dec 12 "
#     [1]:          "Fri"
#     [2]:          "Dec"
#     [3]:          "12"
#     [4]:          nil
```

### `match_values_cleared?(scanner)`

Returns whether the scanner's match values are all properly cleared:

```rb
scanner = StringScanner.new('foobarbaz')
match_values_cleared?(scanner) # => true
put_match_values(scanner)
# Basic match values:
#   matched?:       false
#   matched_size:   nil
#   pre_match:      nil
#   matched  :      nil
#   post_match:     nil
# Captured match values:
#   size:           nil
#   captures:       nil
#   named_captures: {}
#   values_at:      nil
#   [0]:            nil
scanner.scan(/foo/)
match_values_cleared?(scanner) # => false
```

## The Code

```rb
def put_situation(scanner)
  puts '# Situation:'
  puts "#   pos:       #{scanner.pos}"
  puts "#   charpos:   #{scanner.charpos}"
  puts "#   rest:      #{scanner.rest.inspect}"
  puts "#   rest_size: #{scanner.rest_size}"
end

def put_match_values(scanner)
  puts '# Basic match values:'
  puts "#   matched?:       #{scanner.matched?}"
  value = scanner.matched_size || 'nil'
  puts "#   matched_size:   #{value}"
  puts "#   pre_match:      #{scanner.pre_match.inspect}"
  puts "#   matched  :      #{scanner.matched.inspect}"
  puts "#   post_match:     #{scanner.post_match.inspect}"
  puts '# Captured match values:'
  puts "#   size:           #{scanner.size}"
  puts "#   captures:       #{scanner.captures}"
  puts "#   named_captures: #{scanner.named_captures}"
  if scanner.size.nil?
    puts "#   values_at:      #{scanner.values_at(0)}"
    puts "#   [0]:            #{scanner[0]}"
  else
    puts "#   values_at:      #{scanner.values_at(*(0..scanner.size))}"
    puts "#   []:"
    scanner.size.times do |i|
      puts "#     [#{i}]:          #{scanner[i].inspect}"
    end
  end
end

def match_values_cleared?(scanner)
  scanner.matched? == false &&
    scanner.matched_size.nil? &&
    scanner.matched.nil? &&
    scanner.pre_match.nil? &&
    scanner.post_match.nil? &&
    scanner.size.nil? &&
    scanner[0].nil? &&
    scanner.captures.nil? &&
    scanner.values_at(0..1).nil? &&
    scanner.named_captures == {}
end
```

