Returns the offset (in bytes) of the beginning of the specified match.

With non-negative integer argument `n` given,
returns the offset of the beginning of the `n`th match:

```ruby
regexp = /(\d{4})-(\d{2})-(\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" 1:"2026" 2:"12" 3:"25">
match[0]            # => "2026-12-25"
match.bytebegin(0)  # => 0
match[2]            # => "12"
match.bytebegin(2)  # => 5
match.bytebegin(20) # Raises IndexError: index 20 out of matches.

match = /(ん)(に)(ち)/.match('こんにちは')
# => #<MatchData "んにち" 1:"ん" 2:"に" 3:"ち">
match[2]           # => "に"
match.bytebegin(2) # => 6  # Byte offset.
match.begin(2)     # => 2  # Character offset.
```

With string or symbol argument `name` given,
returns the offset of the beginning for the named match:

```ruby
regexp = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/
match = '2026-12-25'.match(regexp)
# => #<MatchData "2026-12-25" year:"2026" month:"12" day:"25">
match[:month]           # => "12"
match.bytebegin(:month) # => 5
match.bytebegin('day')  # => 8
```

Related: MatchData#begin.
