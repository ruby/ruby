# frozen_string_literal: true

class StringScanner
  # :markup: markdown
  #
  # call-seq:
  #   scan_integer(base: 10) -> integer or nil
  #
  # Returns an integer scanned from `self`,
  # beginning at the current position;
  # returns `nil` if no such integer was available.
  #
  # When `base` is `10` (the default),
  # equivalent to calling #scan with argument +pattern+
  # as `'[+-]?\d+'`:
  #
  # ```ruby
  # scanner = StringScanner.new('Form 27B/6')
  # scanner.scan_integer # => nil # No integer at position 0.
  # scanner.pos = 5
  # scanner.scan_integer # => 27
  # scanner.matched      # => "27"
  # scanner.pos          # => 7
  # ```
  #
  # When `base` is `16` (the only other value allowed),
  # equivalent to calling #scan with argument `pattern`
  # as `'[+-]?(0x)?[0-9a-fA-F]+'`:
  #
  # ```ruby
  # scanner.pos = 5
  # scanner.scan_integer(base: 16) # => 635
  # scanner.matched                # => "27B"
  # scanner.pos                    # => 8
  # ```
  #
  # Raises Encoding::CompatibilityError if `self` does not have
  # an ASCII compatible encoding.
  def scan_integer(base: 10)
    case base
    when 10
      scan_base10_integer
    when 16
      scan_base16_integer
    else
      raise ArgumentError, "Unsupported integer base: #{base.inspect}, expected 10 or 16"
    end
  end
end
