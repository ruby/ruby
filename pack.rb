class Array
  #  call-seq:
  #    pack(template, buffer: nil) -> string
  #
  #  Formats each element in +self+ into a binary string; returns that string.
  #  See {Packed Data}[rdoc-ref:language/packed_data.rdoc].
  def pack(fmt, buffer: nil)
    Primitive.pack_pack(fmt, buffer)
  end
end

class String
  #  call-seq:
  #    unpack(template, offset: 0) {|o| .... } -> object
  #    unpack(template, offset: 0) -> array
  #
  #  Extracts data from +self+ to form new objects;
  #  see {Packed Data}[rdoc-ref:language/packed_data.rdoc].
  #
  #  With a block given, calls the block with each unpacked object.
  #
  #  With no block given, returns an array containing the unpacked objects.
  #
  #  Related: see {Converting to Non-String}[rdoc-ref:String@Converting+to+Non--5CString].
  def unpack(fmt, offset: 0)
    Primitive.attr! :use_block
    Primitive.pack_unpack(fmt, offset)
  end

  # call-seq:
  #   unpack1(template, offset: 0) -> object
  #
  #  Like String#unpack with no block, but unpacks and returns only the first extracted object.
  #  See {Packed Data}[rdoc-ref:language/packed_data.rdoc].
  #
  #  Related: see {Converting to Non-String}[rdoc-ref:String@Converting+to+Non--5CString].
  def unpack1(fmt, offset: 0)
    Primitive.pack_unpack1(fmt, offset)
  end
end
