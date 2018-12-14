require 'bigdecimal.so'

def BigDecimal.new(*args, **kwargs)
  warn "BigDecimal.new is deprecated; use BigDecimal() method instead.", uplevel: 1
  BigDecimal(*args, **kwargs)
end
