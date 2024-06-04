call-seq:
  get_byte -> byte_as_character or nil

Returns the next byte, if available:

- If the [position][2]
  is not at the end of the [stored string][1]:

    - Returns the next byte.
    - Increments the [byte position][2].
    - Adjusts the [character position][7].

    ```
    scanner = StringScanner.new(HIRAGANA_TEXT)
    # => #<StringScanner 0/15 @ "\xE3\x81\x93\xE3\x82...">
    scanner.string                                   # => "こんにちは"
    [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\xE3", 1, 1]
    [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x81", 2, 2]
    [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x93", 3, 1]
    [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\xE3", 4, 2]
    [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x82", 5, 3]
    [scanner.get_byte, scanner.pos, scanner.charpos] # => ["\x93", 6, 2]
    ```

- Otherwise, returns `nil`, and does not change the positions.

    ```
    scanner.terminate
    [scanner.get_byte, scanner.pos, scanner.charpos] # => [nil, 15, 5]
    ```
