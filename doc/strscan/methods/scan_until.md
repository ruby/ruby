call-seq:
  scan_until(pattern) -> substring or nil

Attempts to [match][17] the given `pattern`
anywhere (at any [position][2]) in the [target substring][3].

If the match attempt succeeds:

- Sets [match values][9].
- Sets the [byte position][2] to the end of the matched substring;
  may adjust the [character position][7].
- Returns the matched substring.


```rb
scanner = StringScanner.new(HIRAGANA_TEXT)
scanner.string           # => "こんにちは"
scanner.pos = 6
scanner.scan_until(/ち/) # => "にち"
put_match_values(scanner)
# Basic match values:
#   matched?:       true
#   matched_size:   3
#   pre_match:      "こんに"
#   matched  :      "ち"
#   post_match:     "は"
# Captured match values:
#   size:           1
#   captures:       []
#   named_captures: {}
#   values_at:      ["ち", nil]
#   []:
#     [0]:          "ち"
#     [1]:          nil
put_situation(scanner)
# Situation:
#   pos:       12
#   charpos:   4
#   rest:      "は"
#   rest_size: 3
```

If the match attempt fails:

- Clears match data.
- Returns `nil`.
- Does not update positions.

```rb
scanner.scan_until(/nope/)     # => nil
match_values_cleared?(scanner) # => true
```
