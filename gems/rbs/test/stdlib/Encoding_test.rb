require_relative "test_helper"

class EncodingTest < StdlibTest
  target Encoding
  using hook.refinement

  def test_class_method_aliases
    Encoding.aliases
  end

  def test_class_method_compatible?
    Encoding.compatible?("", Encoding::UTF_8)
  end

  def test_class_method_default_external
    Encoding.default_external
  end

  def test_class_method_default_external=
    original = Encoding.default_external

    Encoding.default_external = "utf-8"
    Encoding.default_external = Encoding::UTF_8
  ensure
    Encoding.default_external = original
  end

  def test_class_method_default_internal
    Encoding.default_internal
  end

  def test_class_method_default_internal=
    original = Encoding.default_internal

    Encoding.default_internal = "utf-8"
    Encoding.default_internal = Encoding::UTF_8
  ensure
    Encoding.default_internal = original
  end

  def test_class_method_find
    Encoding.find("utf-8")
    Encoding.find(Encoding::UTF_8)
  end

  def test_class_method_list
    Encoding.list
  end

  def test_class_method_name_list
    Encoding.name_list
  end

  def test_inspect
    Encoding::UTF_8.inspect
  end

  def test_to_s
    Encoding::UTF_8.to_s
  end

  def test_ascii_compatible?
    Encoding::UTF_8.ascii_compatible?
  end

  def test_dummy?
    Encoding::UTF_8.dummy?
  end

  def test_name
    Encoding::UTF_8.name
  end

  def test_names
    Encoding::UTF_8.names
  end

  def test_replicate
    Encoding::UTF_8.replicate("a")
  end
end
