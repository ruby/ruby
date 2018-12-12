class Logger
  class Error < RuntimeError # :nodoc:
  end
  # not used after 1.2.7. just for compat.
  class ShiftingError < Error # :nodoc:
  end
end
