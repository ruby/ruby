require "-test-/memory_view"
require "rbconfig/sizeof"

class TestMemoryView < Test::Unit::TestCase
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

    actual, = MemoryViewTestUtils.item_size_from_format("3c")
    assert_equal(3, actual)

    actual, = MemoryViewTestUtils.item_size_from_format("fd")
    assert_equal(12, actual)

    actual, = MemoryViewTestUtils.item_size_from_format("f2xd")
    assert_equal(14, actual)
  end

  def test_rb_memory_view_item_size_from_format_error
    assert_equal([-1, "a"], MemoryViewTestUtils.item_size_from_format("ccca"))
    assert_equal([-1, "4a"], MemoryViewTestUtils.item_size_from_format("ccc4a"))
  end

  def test_rb_memory_view_parse_item_format
    total_size, members, err = MemoryViewTestUtils.parse_item_format("cc2c3f2x4dq!")
    assert_equal(58, total_size)
    assert_nil(err)
    assert_equal([
                   {format: 'c', native_size_p: false, offset:  0, size: 1, repeat: 1},
                   {format: 'c', native_size_p: false, offset:  1, size: 1, repeat: 1},
                   {format: 'c', native_size_p: false, offset:  2, size: 1, repeat: 2},
                   {format: 'f', native_size_p: false, offset:  4, size: 4, repeat: 3},
                   {format: 'd', native_size_p: false, offset: 18, size: 8, repeat: 4},
                   {format: 'q', native_size_p: true,  offset: 50, size: sizeof('long long'), repeat: 1}
                 ],
                 members)
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

  def test_rb_memory_view_fill_contiguous_strides
    row_major_strides = MemoryViewTestUtils.fill_contiguous_strides(3, 8, [2, 3, 4], true)
    assert_equal([96, 32, 8],
                 row_major_strides)

    column_major_strides = MemoryViewTestUtils.fill_contiguous_strides(3, 8, [2, 3, 4], false)
    assert_equal([8, 16, 48],
                 column_major_strides)
  end
end
