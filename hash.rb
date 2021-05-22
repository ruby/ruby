class Hash
  # call-seq:
  #   hash.include?(key) -> true or false
  #
  # Methods #has_key?, #key?, and #member? are aliases for \#include?.
  #
  # Returns +true+ if +key+ is a key in +self+, otherwise +false+.
  def include?(key)
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_hash_has_key(self, key)'
  end

  # call-seq:
  #   hash.member?(key) -> true or false
  #
  # Returns +true+ if +key+ is a key in +self+, otherwise +false+.
  def member?(key)
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_hash_has_key(self, key)'
  end

  # call-seq:
  #   hash.has_key?(key) -> true or false
  #
  # Returns +true+ if +key+ is a key in +self+, otherwise +false+.
  def has_key?(key)
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_hash_has_key(self, key)'
  end

  # call-seq:
  #   hash.key?(key) -> true or false
  #
  # Returns +true+ if +key+ is a key in +self+, otherwise +false+.
  def key?(key)
    Primitive.attr! 'inline'
    Primitive.cexpr! 'rb_hash_has_key(self, key)'
  end
end
