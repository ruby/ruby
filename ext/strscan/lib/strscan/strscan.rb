# frozen_string_literal: true

class StringScanner
  # call-seq:
  #   scan_integer(base: 10)
  #
  # If `base` isn't provided or is `10`, then it is equivalent to calling `#scan` with a `[+-]?\d+` pattern,
  # and returns an Integer or nil.
  #
  # If `base` is `16`, then it is equivalent to calling `#scan` with a `[+-]?(0x)?[0-9a-fA-F]+` pattern,
  # and returns an Integer or nil.
  #
  # The scanned string must be encoded with an ASCII compatible encoding, otherwise
  # Encoding::CompatibilityError will be raised.
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
