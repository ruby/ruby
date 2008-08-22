require 'cmath'

Object.instance_eval{remove_const :Math}
Math = CMath

def Complex.generic? (other)
  other.kind_of?(Integer) ||
  other.kind_of?(Float)   ||
  other.kind_of?(Rational)
end
