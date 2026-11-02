Returns the offset (in bytes) of the end of the specified match.

When non-negative integer argument `n` is given,
returns the offset of the end of the `n`th match:

```ruby
regexp = /(\d{4})-(\d{2})-(\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" 1:"2026" 2:"12" 3:"25">
match[1]         # => "2026"
match.byteend(1) # => 4
match[3]         # => "25"
match.byteend(3) # => 10
match.byteend(4) # Raises IndexError: index 4 out of matches.

match = /(ん)(に)(ち)/.match('こんにちは')
# => #<MatchData "んにち" 1:"ん" 2:"に" 3:"ち">
match[1]         # => "ん"
match.byteend(1) # => 6  # Byte offset.
match.end(1)     # => 2  # Character offset.
```

When string or symbol argument `name` is given,
returns the offset of the end for the named match:

```ruby
regexp = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" year:"2026" month:"12" day:"25">
match[:year]         # => "2026"
match.byteend(:year) # => 4
match['day']         # => "25"
match.byteend('day') # => 10
```

Related: MatchData#bytebegin.
