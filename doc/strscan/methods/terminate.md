call-seq:
  terminate -> self

Sets the scanner to end-of-string;
returns +self+:

- Sets both [positions][11] to end-of-stream.
- Clears [match values][9].

```rb
scanner = StringScanner.new(HIRAGANA_TEXT)
scanner.string                 # => "こんにちは"
scanner.scan_until(/に/)
put_situation(scanner)
# Situation:
#   pos:       9
#   charpos:   3
#   rest:      "ちは"
#   rest_size: 6
match_values_cleared?(scanner) # => false

scanner.terminate              # => #<StringScanner fin>
put_situation(scanner)
# Situation:
#   pos:       15
#   charpos:   5
#   rest:      ""
#   rest_size: 0
match_values_cleared?(scanner) # => true
```
