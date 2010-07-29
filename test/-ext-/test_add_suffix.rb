require 'test/unit'
require "-test-/add_suffix/bug"

class Test_AddSuffix < Test::Unit::TestCase
  Dir = "/dev/null/".freeze
  Style_1 = (Dir+"foo").freeze

  def test_style_0
    assert_equal("a.x.y", Bug.add_suffix("a.x", ".y"))
  end

  def test_style_1
    assert_equal(Style_1+".y", Bug.add_suffix(Style_1+".c", ".y"))
    suffix = ".bak".freeze
    assert_equal(Style_1+suffix, Bug.add_suffix(Style_1.dup, suffix))
    assert_equal(Style_1+suffix, Bug.add_suffix(Style_1+".bar", suffix))
    assert_equal(Style_1+".$$$", Bug.add_suffix(Style_1+suffix, suffix))
    assert_equal(Style_1+suffix, Bug.add_suffix(Style_1+".$$$", suffix))
    assert_equal(Style_1+".~~~", Bug.add_suffix(Style_1+".$$$", ".$$$"))
    assert_equal(Dir+"makefile"+suffix, Bug.add_suffix(Dir+"makefile", suffix))
  end

  def test_style_2
    suffix = "~"
    assert_equal(Style_1+"~", Bug.add_suffix(Style_1.dup, suffix))
    assert_equal(Style_1+".c~", Bug.add_suffix(Style_1+".c", suffix))
    assert_equal(Style_1+".c~~", Bug.add_suffix(Style_1+".c~", suffix))
    assert_equal(Style_1+"~.c~~", Bug.add_suffix(Style_1+".c~~", suffix))
    assert_equal(Style_1+"~~.c~~", Bug.add_suffix(Style_1+"~.c~~", suffix))
    assert_equal(Style_1+"~~~~~.cc~", Bug.add_suffix(Style_1+"~~~~~.ccc", suffix))
    assert_equal(Style_1+"~~~~~.$$$", Bug.add_suffix(Style_1+"~~~~~.c~~", suffix))
    assert_equal(Dir+"foo~.pas", Bug.add_suffix(Dir+"foo.pas", suffix))
    assert_equal(Dir+"makefile.~", Bug.add_suffix(Dir+"makefile", suffix))
    assert_equal(Dir+"longname.fi~", Bug.add_suffix(Dir+"longname.fil", suffix))
    assert_equal(Dir+"longnam~.fi~", Bug.add_suffix(Dir+"longname.fi~", suffix))
    assert_equal(Dir+"longnam~.$$$", Bug.add_suffix(Dir+"longnam~.fi~", suffix))
  end

  def test_style_3
    base = "a"*1000
    suffix = "-"+"b"*1000
    assert_equal(base+".~~~", Bug.add_suffix(base, suffix))
    assert_equal(base+".~~~", Bug.add_suffix(base+".$$$", suffix))
    assert_equal(base+".$$$", Bug.add_suffix(base+".~~~", suffix))
  end
end
