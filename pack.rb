class Array
  #  call-seq:
  #    pack(template, buffer: nil) -> string
  #
  #  Formats each element in +self+ into a binary string; returns that string.
  #  See {Packed Data}[rdoc-ref:packed_data.rdoc].
  def pack(fmt, buffer: nil)
    Primitive.pack_pack(fmt, buffer)
  end
end

class String
  # call-seq:
  #   unpack(template, offset: 0) -> array
  #
  #  Extracts data from +self+, forming objects that become the elements of a new array;
  #  returns that array.
  #  See {Packed Data}[rdoc-ref:packed_data.rdoc].
  def unpack(fmt, offset: 0)
    Primitive.attr! :use_block
    Primitive.pack_unpack(fmt, offset)
  end

  # call-seq:
  #   unpack1(template, offset: 0) -> object
  #
  #  Like String#unpack, but unpacks and returns only the first extracted object.
  #  See {Packed Data}[rdoc-ref:packed_data.rdoc].
  def unpack1(fmt, offset: 0)
    Primitive.pack_unpack1(fmt, offset)
  end
end
