require "-test-/memory_view"
require "rbconfig/sizeof"

class TestMemoryView < Test::Unit::TestCase
  NATIVE_ENDIAN = MemoryViewTestUtils::NATIVE_ENDIAN
  LITTLE_ENDIAN = :little_endian
  BIG_ENDIAN    = :big_endian

  %I(SHORT INT INT16 INT32 INT64 INTPTR LONG LONG_LONG FLOAT DOUBLE).each do |type|
    name = :"#{type}_ALIGNMENT"
    const_set(name, MemoryViewTestUtils.const_get(name))
  end

  def test_rb_memory_view_register_duplicated
    assert_warning(/Duplicated registration of memory view to/) do
      MemoryViewTestUtils.register(MemoryViewTestUtils::ExportableString)
    end
  end

  def test_rb_memory_view_register_nonclass
    assert_raise(TypeError) do
      MemoryViewTestUtils.register(Object.new)
    end
  end

  def sizeof(type)
    RbConfig::SIZEOF[type.to_s]
  end

  def test_rb_memory_view_item_size_from_format
    [
      [nil, 1], ['c', 1], ['C', 1],
      ['n', 2], ['v', 2],
      ['l', 4], ['L', 4], ['N', 4], ['V', 4], ['f', 4], ['e', 4], ['g', 4],
      ['q', 8], ['Q', 8], ['d', 8], ['E', 8], ['G', 8],
      ['s', sizeof(:short)], ['S', sizeof(:short)], ['s!', sizeof(:short)], ['S!', sizeof(:short)],
      ['i', sizeof(:int)], ['I', sizeof(:int)], ['i!', sizeof(:int)], ['I!', sizeof(:int)],
      ['l!', sizeof(:long)], ['L!', sizeof(:long)],
      ['q!', sizeof('long long')], ['Q!', sizeof('long long')],
      ['j', sizeof(:intptr_t)], ['J', sizeof(:intptr_t)],
    ].each do |format, expected|
      actual, err = MemoryViewTestUtils.item_size_from_format(format)
      assert_nil(err)
      assert_equal(expected, actual, "rb_memory_view_item_size_from_format(#{format || 'NULL'}) == #{expected}")
    end
  end

  def test_rb_memory_view_item_size_from_format_composed
    actual, = MemoryViewTestUtils.item_size_from_format("ccc")
    assert_equal(3, actual)

    actual, = MemoryViewTestUtils.item_size_from_format("c3")
    assert_equal(3, actual)

    actual, = MemoryViewTestUtils.item_size_from_format("fd")
    assert_equal(12, actual)

    actual, = MemoryViewTestUtils.item_size_from_format("fx2d")
    assert_equal(14, actual)
  end

  def test_rb_memory_view_item_size_from_format_with_spaces
    # spaces should be ignored
    actual, = MemoryViewTestUtils.item_size_from_format("f x2 d")
    assert_equal(14, actual)
  end

  def test_rb_memory_view_item_size_from_format_error
    assert_equal([-1, "a"], MemoryViewTestUtils.item_size_from_format("ccca"))
    assert_equal([-1, "a"], MemoryViewTestUtils.item_size_from_format("ccc4a"))
  end

  def test_rb_memory_view_parse_item_format
    total_size, members, err = MemoryViewTestUtils.parse_item_format("ccc2f3x2d4q!<")
    assert_equal(58, total_size)
    assert_nil(err)
    assert_equal([
                   {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN, offset:  0, size: 1, repeat: 1},
                   {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN, offset:  1, size: 1, repeat: 1},
                   {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN, offset:  2, size: 1, repeat: 2},
                   {format: 'f', native_size_p: false, endianness: NATIVE_ENDIAN, offset:  4, size: 4, repeat: 3},
                   {format: 'd', native_size_p: false, endianness: NATIVE_ENDIAN, offset: 18, size: 8, repeat: 4},
                   {format: 'q', native_size_p: true,  endianness: :little_endian, offset: 50, size: sizeof('long long'), repeat: 1}
                 ],
                 members)
  end

  def test_rb_memory_view_parse_item_format_with_alignment_signle
    [
      ["c",  false, NATIVE_ENDIAN,  1,               1,              1],
      ["C",  false, NATIVE_ENDIAN,  1,               1,              1],
      ["s",  false, NATIVE_ENDIAN,  SHORT_ALIGNMENT, sizeof(:short), 1],
      ["S",  false, NATIVE_ENDIAN,  SHORT_ALIGNMENT, sizeof(:short), 1],
      ["s!", true,  NATIVE_ENDIAN,  SHORT_ALIGNMENT, sizeof(:short), 1],
      ["S!", true,  NATIVE_ENDIAN,  SHORT_ALIGNMENT, sizeof(:short), 1],
      ["n",  false, :big_endian,    INT16_ALIGNMENT, sizeof(:int16_t), 1],
      ["v",  false, :little_endian, INT16_ALIGNMENT, sizeof(:int16_t), 1],
      ["i",  false, NATIVE_ENDIAN,  INT_ALIGNMENT, sizeof(:int), 1],
      ["I",  false, NATIVE_ENDIAN,  INT_ALIGNMENT, sizeof(:int), 1],
      ["i!", true,  NATIVE_ENDIAN,  INT_ALIGNMENT, sizeof(:int), 1],
      ["I!", true,  NATIVE_ENDIAN,  INT_ALIGNMENT, sizeof(:int), 1],
      ["l",  false, NATIVE_ENDIAN,  INT32_ALIGNMENT, sizeof(:int32_t), 1],
      ["L",  false, NATIVE_ENDIAN,  INT32_ALIGNMENT, sizeof(:int32_t), 1],
      ["l!", true,  NATIVE_ENDIAN,  LONG_ALIGNMENT, sizeof(:long), 1],
      ["L!", true,  NATIVE_ENDIAN,  LONG_ALIGNMENT, sizeof(:long), 1],
      ["N",  false, :big_endian,    INT32_ALIGNMENT, sizeof(:int32_t), 1],
      ["V",  false, :little_endian, INT32_ALIGNMENT, sizeof(:int32_t), 1],
      ["f",  false, NATIVE_ENDIAN,  FLOAT_ALIGNMENT, sizeof(:float), 1],
      ["e",  false, :little_endian, FLOAT_ALIGNMENT, sizeof(:float), 1],
      ["g",  false, :big_endian,    FLOAT_ALIGNMENT, sizeof(:float), 1],
      ["q",  false, NATIVE_ENDIAN,  INT64_ALIGNMENT, sizeof(:int64_t), 1],
      ["Q",  false, NATIVE_ENDIAN,  INT64_ALIGNMENT, sizeof(:int64_t), 1],
      ["q!", true,  NATIVE_ENDIAN,  LONG_LONG_ALIGNMENT, sizeof("long long"), 1],
      ["Q!", true,  NATIVE_ENDIAN,  LONG_LONG_ALIGNMENT, sizeof("long long"), 1],
      ["d",  false, NATIVE_ENDIAN,  DOUBLE_ALIGNMENT, sizeof(:double), 1],
      ["E",  false, :little_endian, DOUBLE_ALIGNMENT, sizeof(:double), 1],
      ["G",  false, :big_endian,    DOUBLE_ALIGNMENT, sizeof(:double), 1],
      ["j",  false, NATIVE_ENDIAN,  INTPTR_ALIGNMENT, sizeof(:intptr_t), 1],
      ["J",  false, NATIVE_ENDIAN,  INTPTR_ALIGNMENT, sizeof(:intptr_t), 1],
    ].each do |type, native_size_p, endianness, alignment, size, repeat, total_size|
      total_size, members, err = MemoryViewTestUtils.parse_item_format("|c#{type}")
      assert_nil(err)

      padding_size = alignment - 1
      expected_total_size = 1 + padding_size + size
      assert_equal(expected_total_size, total_size)

      expected_result = [
        {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN,  offset: 0, size: 1, repeat: 1},
        {format: type[0], native_size_p: native_size_p, endianness: endianness,  offset: alignment, size: size, repeat: repeat},
      ]
      assert_equal(expected_result, members)
    end
  end

  def alignment_padding(total_size, alignment)
    res = total_size % alignment
    if res > 0
      alignment - res
    else
      0
    end
  end

  def test_rb_memory_view_parse_item_format_with_alignment_total_size_with_tail_padding
    total_size, _members, err = MemoryViewTestUtils.parse_item_format("|lqc")
    assert_nil(err)

    expected_total_size = sizeof(:int32_t)
    expected_total_size += alignment_padding(expected_total_size, INT32_ALIGNMENT)
    expected_total_size += sizeof(:int64_t)
    expected_total_size += alignment_padding(expected_total_size, INT64_ALIGNMENT)
    expected_total_size += 1
    expected_total_size += alignment_padding(expected_total_size, INT64_ALIGNMENT)
    assert_equal(expected_total_size, total_size)
  end

  def test_rb_memory_view_parse_item_format_with_alignment_compound
    total_size, members, err = MemoryViewTestUtils.parse_item_format("|ccc2f3x2d4cq!<")
    assert_nil(err)

    expected_total_size = 1 + 1 + 1*2
    expected_total_size += alignment_padding(expected_total_size, FLOAT_ALIGNMENT)
    expected_total_size += sizeof(:float)*3 + 1*2
    expected_total_size += alignment_padding(expected_total_size, DOUBLE_ALIGNMENT)
    expected_total_size += sizeof(:double)*4 + 1
    expected_total_size += alignment_padding(expected_total_size, LONG_LONG_ALIGNMENT)
    expected_total_size += sizeof("long long")
    assert_equal(expected_total_size, total_size)

    expected_result = [
      {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN,  offset:  0, size: 1, repeat: 1},
      {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN,  offset:  1, size: 1, repeat: 1},
      {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN,  offset:  2, size: 1, repeat: 2},
    ]
    offset = 4

    res = offset % FLOAT_ALIGNMENT
    offset += FLOAT_ALIGNMENT - res if res > 0
    expected_result << {format: 'f', native_size_p: false, endianness: NATIVE_ENDIAN, offset: offset, size: 4, repeat: 3}
    offset += 12

    offset += 2 # 2x

    res = offset % DOUBLE_ALIGNMENT
    offset += DOUBLE_ALIGNMENT - res if res > 0
    expected_result << {format: 'd', native_size_p: false, endianness: NATIVE_ENDIAN, offset: offset, size: 8, repeat: 4}
    offset += 32

    expected_result << {format: 'c', native_size_p: false, endianness: NATIVE_ENDIAN,  offset: offset, size: 1, repeat: 1}
    offset += 1

    res = offset % LONG_LONG_ALIGNMENT
    offset += LONG_LONG_ALIGNMENT - res if res > 0
    expected_result << {format: 'q', native_size_p: true, endianness: :little_endian, offset: offset, size: 8, repeat: 1}

    assert_equal(expected_result, members)
  end

  def test_rb_memory_view_extract_item_members
    m = MemoryViewTestUtils
    assert_equal(1, m.extract_item_members([1].pack("c"), "c"))
    assert_equal([1, 2], m.extract_item_members([1, 2].pack("ii"), "ii"))
    assert_equal([1, 2, 3], m.extract_item_members([1, 2, 3].pack("cls"), "cls"))
  end

  def test_rb_memory_view_extract_item_members_endianness
    m = MemoryViewTestUtils
    assert_equal([0x0102, 0x0304], m.extract_item_members([1, 2, 3, 4].pack("c*"), "S>2"))
    assert_equal([0x0102, 0x0304], m.extract_item_members([1, 2, 3, 4].pack("c*"), "n2"))
    assert_equal([0x0201, 0x0403], m.extract_item_members([1, 2, 3, 4].pack("c*"), "S<2"))
    assert_equal([0x0201, 0x0403], m.extract_item_members([1, 2, 3, 4].pack("c*"), "v2"))
    assert_equal(0x01020304, m.extract_item_members([1, 2, 3, 4].pack("c*"), "L>"))
    assert_equal(0x01020304, m.extract_item_members([1, 2, 3, 4].pack("c*"), "N"))
    assert_equal(0x04030201, m.extract_item_members([1, 2, 3, 4].pack("c*"), "L<"))
    assert_equal(0x04030201, m.extract_item_members([1, 2, 3, 4].pack("c*"), "V"))
    assert_equal(0x0102030405060708, m.extract_item_members([1, 2, 3, 4, 5, 6, 7, 8].pack("c*"), "Q>"))
    assert_equal(0x0807060504030201, m.extract_item_members([1, 2, 3, 4, 5, 6, 7, 8].pack("c*"), "Q<"))
  end

  def test_rb_memory_view_extract_item_members_float
    m = MemoryViewTestUtils
    packed = [1.23].pack("f")
    assert_equal(packed.unpack("f")[0], m.extract_item_members(packed, "f"))
  end

  def test_rb_memory_view_extract_item_members_float_endianness
    m = MemoryViewTestUtils
    hi, lo = [1.23].pack("f").unpack("L")[0].divmod(0x10000)
    packed = [lo, hi].pack("S*")
    assert_equal(packed.unpack("e")[0], m.extract_item_members(packed, "e"))
    packed = [hi, lo].pack("S*")
    assert_equal(packed.unpack("g")[0], m.extract_item_members(packed, "g"))
  end

  def test_rb_memory_view_extract_item_members_doble
    m = MemoryViewTestUtils
    packed = [1.23].pack("d")
    assert_equal(1.23, m.extract_item_members(packed, "d"))
  end

  def test_rb_memory_view_extract_item_members_doble_endianness
    m = MemoryViewTestUtils
    hi, lo = [1.23].pack("d").unpack("Q")[0].divmod(0x10000)
    packed = [lo, hi].pack("L*")
    assert_equal(packed.unpack("E")[0], m.extract_item_members(packed, "E"))
    packed = [hi, lo].pack("L*")
    assert_equal(packed.unpack("G")[0], m.extract_item_members(packed, "G"))
  end

  def test_rb_memory_view_available_p
    es = MemoryViewTestUtils::ExportableString.new("ruby")
    assert_equal(true, MemoryViewTestUtils.available?(es))
    es = MemoryViewTestUtils::ExportableString.new(nil)
    assert_equal(false, MemoryViewTestUtils.available?(es))
  end

  def test_ref_count_with_exported_object
    es = MemoryViewTestUtils::ExportableString.new("ruby")
    assert_equal(1, MemoryViewTestUtils.ref_count_while_exporting(es, 1))
    assert_equal(2, MemoryViewTestUtils.ref_count_while_exporting(es, 2))
    assert_equal(10, MemoryViewTestUtils.ref_count_while_exporting(es, 10))
    assert_nil(MemoryViewTestUtils.ref_count_while_exporting(es, 0))
  end

  def test_rb_memory_view_init_as_byte_array
    # ExportableString's memory view is initialized by rb_memory_view_init_as_byte_array
    es = MemoryViewTestUtils::ExportableString.new("ruby")
    memory_view_info = MemoryViewTestUtils.get_memory_view_info(es)
    assert_equal({
                   obj: es,
                   len: 4,
                   readonly: true,
                   format: nil,
                   item_size: 1,
                   ndim: 1,
                   shape: nil,
                   strides: nil,
                   sub_offsets: nil
                 },
                 memory_view_info)
  end

  def test_rb_memory_view_get_with_memory_view_unavailable_object
    es = MemoryViewTestUtils::ExportableString.new(nil)
    memory_view_info = MemoryViewTestUtils.get_memory_view_info(es)
    assert_nil(memory_view_info)
  end

  def test_rb_memory_view_fill_contiguous_strides
    row_major_strides = MemoryViewTestUtils.fill_contiguous_strides(3, 8, [2, 3, 4], true)
    assert_equal([96, 32, 8],
                 row_major_strides)

    column_major_strides = MemoryViewTestUtils.fill_contiguous_strides(3, 8, [2, 3, 4], false)
    assert_equal([8, 16, 48],
                 column_major_strides)
  end

  def test_rb_memory_view_get_item_pointer_single_member
    buf = [ 1, 2, 3, 4,
            5, 6, 7, 8,
            9, 10, 11, 12 ].pack("l!*")
    shape = [3, 4]
    mv = MemoryViewTestUtils::MultiDimensionalView.new(buf, "l!", shape, nil)
    assert_equal(1, mv[[0, 0]])
    assert_equal(4, mv[[0, 3]])
    assert_equal(6, mv[[1, 1]])
    assert_equal(10, mv[[2, 1]])
  end

  def test_rb_memory_view_get_item_pointer_multiple_members
    buf = [ 1, 2,  3,  4,  5,  6,  7,  8,
            -1, -2, -3, -4, -5, -6, -7, -8].pack("s*")
    shape = [2, 4]
    strides = [4*sizeof(:short)*2, sizeof(:short)*2]
    mv = MemoryViewTestUtils::MultiDimensionalView.new(buf, "ss", shape, strides)
    assert_equal([1, 2], mv[[0, 0]])
    assert_equal([5, 6], mv[[0, 2]])
    assert_equal([-1, -2], mv[[1, 0]])
    assert_equal([-7, -8], mv[[1, 3]])
  end

  def test_ractor
    assert_in_out_err([], <<-"end;", ["[5, 6]", "[-7, -8]"], [])
      require "-test-/memory_view"
      require "rbconfig/sizeof"
      $VERBOSE = nil
      r = Ractor.new RbConfig::SIZEOF["short"] do |sizeof_short|
        buf = [ 1, 2,  3,  4,  5,  6,  7,  8,
                -1, -2, -3, -4, -5, -6, -7, -8].pack("s*")
        shape = [2, 4]
        strides = [4*sizeof_short*2, sizeof_short*2]
        mv = MemoryViewTestUtils::MultiDimensionalView.new(buf, "ss", shape, strides)
        p mv[[0, 2]]
        mv[[1, 3]]
      end
      p r.take
    end;
  end
end
