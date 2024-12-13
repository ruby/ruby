call-seq:
  getch -> character or nil

Returns the next (possibly multibyte) character,
if available:

- If the [position][2]
  is at the beginning of a character:

    - Returns the character.
    - Increments the [character position][7] by 1.
    - Increments the [byte position][2]
      by the size (in bytes) of the character.

    ```rb
    scanner = StringScanner.new(HIRAGANA_TEXT)
    scanner.string                                # => "こんにちは"
    [scanner.getch, scanner.pos, scanner.charpos] # => ["こ", 3, 1]
    [scanner.getch, scanner.pos, scanner.charpos] # => ["ん", 6, 2]
    [scanner.getch, scanner.pos, scanner.charpos] # => ["に", 9, 3]
    [scanner.getch, scanner.pos, scanner.charpos] # => ["ち", 12, 4]
    [scanner.getch, scanner.pos, scanner.charpos] # => ["は", 15, 5]
    [scanner.getch, scanner.pos, scanner.charpos] # => [nil, 15, 5]
    ```

- If the [position][2] is within a multi-byte character
  (that is, not at its beginning),
  behaves like #get_byte (returns a 1-byte character):

    ```rb
    scanner.pos = 1
    [scanner.getch, scanner.pos, scanner.charpos] # => ["\x81", 2, 2]
    [scanner.getch, scanner.pos, scanner.charpos] # => ["\x93", 3, 1]
    [scanner.getch, scanner.pos, scanner.charpos] # => ["ん", 6, 2]
    ```

- If the [position][2] is at the end of the [stored string][1],
  returns `nil` and does not modify the positions:

    ```rb
    scanner.terminate
    [scanner.getch, scanner.pos, scanner.charpos] # => [nil, 15, 5]
    ```
