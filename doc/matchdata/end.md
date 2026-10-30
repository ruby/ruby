Returns the offset (in characters) of the end of the specified match.

With non-negative integer argument `n` given,
returns the character offset of the end of the `n`th match:

```ruby
regexp = /(\d{4})-(\d{2})-(\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" 1:"2026" 2:"12" 3:"25">
match[0]       # => "2026-12-25"
match.end(0)   # => 10
match[3]       # => "25"
match.end(3)   # => 10
match.end(10)  # Raises IndexError: index 10 out of matches.

match = /(ん)(に)(ち)/.match('こんにちは')
# => #<MatchData "んにち" 1:"ん" 2:"に" 3:"ち">
match[2]         # => "に"
match.end(2)     # => 3  # Character offset.
match.byteend(2) # => 9  # Byte offset.
```

With string or symbol argument name given, returns the offset of the end for the named match:

```ruby
regexp = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" year:"2026" month:"12" day:"25">
match[:year]       # => "2026"
match.end(:year)   # => 4
match.end('month') # => 7
```

Related: MatchData#byteend.
