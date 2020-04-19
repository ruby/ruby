require_relative "test_helper"
require "ruby/signature/test/test_helper"

class DirSingletonTest < Minitest::Test
  include Ruby::Signature::Test::TypeAssertions

  testing "singleton(::Dir)"

  def test_new
    assert_send_type "(::String) -> ::Dir", Dir, :new, "."
    assert_send_type "(::ToStr) -> ::Dir", Dir, :new, ToStr.new("..")

    assert_send_type "(::String, encoding: ::Encoding) -> ::Dir",
                     Dir, :new, ".", encoding: Encoding::UTF_8
    assert_send_type "(::String, encoding: ::String) -> ::Dir",
                     Dir, :new, ".", encoding: "ASCII-8BIT"
    assert_send_type "(::String, encoding: ::ToStr) -> ::Dir",
                     Dir, :new, ".", encoding: ToStr.new("ASCII-8BIT")
    assert_send_type "(::String, encoding: nil) -> ::Dir",
                     Dir, :new, ".", encoding: nil
  end

  def test_square_bracket
    assert_send_type "(::String) -> ::Array[::String]",
                     Dir, :[], "*/*"
    assert_send_type "(::ToStr) -> ::Array[::String]",
                     Dir, :[], ToStr.new("*/*")
    assert_send_type "(::String) { (::String) -> void } -> Array[String]",
                     Dir, :[], "*/*" do end
    assert_send_type "(::String, ::String, base: ::String) -> ::Array[::String]",
                     Dir, :[], "*/*", "*", base: __dir__
  end

  def test_chdir
    assert_send_type "() -> Integer",
                     Dir, :chdir
    assert_send_type "(::String) -> Integer",
                     Dir, :chdir, __dir__
    assert_send_type "(::ToStr) -> Integer",
                     Dir, :chdir, ToStr.new(__dir__)
    assert_send_type "(::ToStr) { (::String) -> 30 } -> 30",
                     Dir, :chdir, ToStr.new(__dir__) do 30 end
  end

  def test_children
    assert_send_type "(::ToStr) -> ::Array[::String]",
                     Dir, :children, ToStr.new(__dir__)
    assert_send_type "(::ToStr, encoding: Encoding) -> ::Array[::String]",
                     Dir, :children, ToStr.new(__dir__), encoding: Encoding::UTF_8
    assert_send_type "(::ToStr, encoding: ::ToStr) -> ::Array[::String]",
                     Dir, :children, ToStr.new(__dir__), encoding: ToStr.new("UTF-8")
    assert_send_type "(::ToStr, encoding: nil) -> ::Array[::String]",
                     Dir, :children, ToStr.new(__dir__), encoding: nil
  end

  def test_delete
    Dir.mktmpdir do |d|
      File.join(d, "foo").tap do |path|
        Dir.mkdir path
        assert_send_type "(::ToStr) -> ::Integer",
                         Dir, :delete, ToStr.new(path)
      end

      File.join(d, "bar").tap do |path|
        Dir.mkdir path
        assert_send_type "(::ToStr) -> ::Integer",
                         Dir, :rmdir, ToStr.new(path)
      end
    end
  end

  def test_each_child
    assert_send_type "(::String) { (::String) -> 3 } -> nil",
                     Dir, :each_child, "." do 3 end
    assert_send_type "(::ToStr, encoding: nil) { (::String) -> 3 } -> nil",
                     Dir, :each_child, ToStr.new("."), encoding: nil do 3 end

    assert_send_type "(::String) -> ::Enumerator[::String, void]",
                     Dir, :each_child, "."
  end

  def test_empty?
    assert_send_type "(::String) -> bool",
                     Dir, :empty?, "."
    assert_send_type "(::ToStr) -> bool",
                     Dir, :empty?, ToStr.new("../")
  end

  def test_entries
    assert_send_type "(::String) -> ::Array[::String]",
                     Dir, :entries, ".."
    assert_send_type "(::ToStr, encoding: ::Encoding) -> ::Array[::String]",
                     Dir, :entries, ToStr.new(".."), encoding: Encoding::UTF_8
    assert_send_type "(::ToStr, encoding: ::Encoding) -> ::Array[::String]",
                     Dir, :entries, ToStr.new(".."), encoding: Encoding::UTF_8
  end

  def test_exist?
    assert_send_type "(::ToStr) -> bool",
                     Dir, :entries, ToStr.new(__dir__)
  end

  def test_foreach
    assert_send_type "(::String) { (::String) -> 3 } -> nil",
                     Dir, :foreach, "." do 3 end
    assert_send_type "(::ToStr, encoding: nil) { (::String) -> 3 } -> nil",
                     Dir, :foreach, ToStr.new("."), encoding: nil do 3 end

    assert_send_type "(::String) -> ::Enumerator[::String, nil]",
                     Dir, :foreach, "."
  end

  def test_getwd
    assert_send_type "() -> ::String",
                     Dir, :getwd
  end

  def test_glob
    assert_send_type "(::String) -> ::Array[::String]",
                     Dir, :glob, "**/*.rbs"
    assert_send_type "(::Array[::ToStr], Integer, base: ::ToStr) -> ::Array[::String]",
                     Dir, :glob, [ToStr.new("test_*.rb")], 0, base: ToStr.new(__dir__)
    assert_send_type "(::String) { (::String) -> 3 } -> nil",
                     Dir, :glob, "**/*.rbs" do 3 end
  end

  def test_home
    assert_send_type "() -> ::String",
                     Dir, :home
    assert_send_type "(::ToStr) -> ::String",
                     Dir, :home, ToStr.new("root")
  end

  def test_mkdir
    Dir.mktmpdir do |path|
      assert_send_type "(::String) -> ::Integer",
                       Dir, :mkdir, File.join(path, "foo")
      assert_send_type "(::String, ::Integer) -> ::Integer",
                       Dir, :mkdir, File.join(path, "bar"), 0700
    end
  end

  def test_open
    assert_send_type "(::String) -> ::Dir",
                     Dir, :open, "."
    assert_send_type "(::String, encoding: String) -> ::Dir",
                     Dir, :open, ".", encoding: 'UTF-8'
    assert_send_type "(::ToStr, encoding: Encoding) -> ::Dir",
                     Dir, :open, ToStr.new("."), encoding: Encoding::UTF_8
    assert_send_type "(::ToStr) { (::Dir) -> 31 } -> 31",
                     Dir, :open, ToStr.new(".") do 31 end
    assert_send_type "(::String, encoding: String) { (::Dir) -> 31 } -> 31",
                     Dir, :open, ".", encoding: 'UTF-8' do 31 end
  end

  def test_pwd
    assert_send_type "() -> ::String",
                     Dir, :pwd
  end
end

class DirInstanceTest < Minitest::Test
  include Ruby::Signature::Test::TypeAssertions

  testing "::Dir"

  def test_children
    assert_send_type "() -> ::Array[::String]",
                     Dir.new("."), :children
  end

  def test_close
    assert_send_type "() -> nil",
                     Dir.new("."), :close
  end

  def test_each
    assert_send_type "() { (::String) -> 11 } -> ::Dir",
                     Dir.new("."), :each do 11 end
    assert_send_type "() -> ::Enumerator[::String, ::Dir]",
                     Dir.new("."), :each
  end

  def test_each_child
    assert_send_type "() { (::String) -> 11 } -> ::Dir",
                     Dir.new("."), :each_child do 11 end
    assert_send_type "() -> ::Enumerator[::String, ::Dir]",
                     Dir.new("."), :each_child
  end

  def test_fileno
    assert_send_type "() -> ::Integer",
                     Dir.new("."), :fileno
  end

  def test_inspect
    assert_send_type "() -> ::String",
                     Dir.new("."), :inspect
  end

  def test_path
    assert_send_type "() -> ::String",
                     Dir.new("/"), :path
    assert_send_type "() -> ::String",
                     Dir.new("/"), :to_path
  end

  def test_pos
    assert_send_type "() -> ::Integer",
                     Dir.new("/"), :pos

    assert_send_type "(::Integer) -> ::Integer",
                     Dir.new("/"), :pos=, 1
  end

  def test_read
    Dir.mktmpdir do |path|
      dir = Dir.new(path)
      assert_send_type "() -> ::String",
                       dir, :read
      assert_send_type "() -> ::String",
                       dir, :read
      assert_send_type "() -> nil",
                       dir, :read
    end
  end

  def test_rewind
    assert_send_type "() -> ::Dir",
                     Dir.new(__dir__), :rewind
  end

  def test_seek
    assert_send_type "(::Integer) -> ::Dir",
                     Dir.new(__dir__), :seek, 1
  end

  def test_tel
    assert_send_type "() -> ::Integer",
                     Dir.new(__dir__), :tell
  end
end
