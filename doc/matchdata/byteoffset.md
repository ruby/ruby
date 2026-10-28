Returns the offsets (in bytes) of the beginning and end of the specified match.

With non-negative integer argument `n` given,
returns the offsets of the `n`th match:

```ruby
regexp = /(\d{4})-(\d{2})-(\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" 1:"2026" 2:"12" 3:"25">
match[1]             # => "2026"
match.byteoffset(1)  # => [0, 4]
match[3]             # => "25"
match.byteoffset(3)  # => [8, 10]
match.byteoffset(10) # Raises IndexError: index 10 out of matches.

match = /(ん)(に)(ち)/.match('こんにちは')
# => #<MatchData "んにち" 1:"ん" 2:"に" 3:"ち">
match[1]            # => "ん"
match.byteoffset(1) # => [3, 6] # Byte offsets.
match.offset(1)     # => [1, 2] # Character offsets.
```

With string or symbol argument `name` given,
returns the offsets of the named match:

```ruby
regexp = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" year:"2026" month:"12" day:"25">
match[:year]            # => "2026"
match.byteoffset(:year) # => [0, 4]
match.byteoffset('day') # => [8, 10]
```


Related: MatchData#offset.
