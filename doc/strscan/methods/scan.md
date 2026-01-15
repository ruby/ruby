call-seq:
  scan(pattern) -> substring or nil

Attempts to [match][17] the given `pattern`
at the beginning of the [target substring][3].

If the match succeeds:

- Returns the matched substring.
- Increments the [byte position][2] by <tt>substring.bytesize</tt>,
  and may increment the [character position][7].
- Sets [match values][9].

```rb
scanner = StringScanner.new(HIRAGANA_TEXT)
scanner.string     # => "こんにちは"
scanner.pos = 6
scanner.scan(/に/) # => "に"
put_match_values(scanner)
# Basic match values:
#   matched?:       true
#   matched_size:   3
#   pre_match:      "こん"
#   matched  :      "に"
#   post_match:     "ちは"
# Captured match values:
#   size:           1
#   captures:       []
#   named_captures: {}
#   values_at:      ["に", nil]
#   []:
#     [0]:          "に"
#     [1]:          nil
put_situation(scanner)
# Situation:
#   pos:       9
#   charpos:   3
#   rest:      "ちは"
#   rest_size: 6
```

If the match fails:

- Returns `nil`.
- Does not increment byte and character positions.
- Clears match values.

```rb
scanner.scan(/nope/)           # => nil
match_values_cleared?(scanner) # => true
```
