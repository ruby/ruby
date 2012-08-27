require "test/unit"
require "etc"

class TestEtc < Test::Unit::TestCase
  def test_getlogin
    s = Etc.getlogin
    assert(s.is_a?(String) || s == nil, "getlogin must return a String or nil")
  end

  def test_passwd
    Etc.passwd do |s|
      assert_instance_of(String, s.name)
      assert_instance_of(String, s.passwd) if s.respond_to?(:passwd)
      assert_kind_of(Integer, s.uid)
      assert_kind_of(Integer, s.gid)
      assert_instance_of(String, s.gecos) if s.respond_to?(:gecos)
      assert_instance_of(String, s.dir)
      assert_instance_of(String, s.shell)
      assert_kind_of(Integer, s.change) if s.respond_to?(:change)
      assert_kind_of(Integer, s.quota) if s.respond_to?(:quota)
      assert(s.age.is_a?(Integer) || s.age.is_a?(String)) if s.respond_to?(:age)
      assert_instance_of(String, s.uclass) if s.respond_to?(:uclass)
      assert_instance_of(String, s.comment) if s.respond_to?(:comment)
      assert_kind_of(Integer, s.expire) if s.respond_to?(:expire)
    end

    Etc.passwd { assert_raise(RuntimeError) { Etc.passwd { } }; break }
  end

  def test_getpwuid
    # password database is not unique on UID, and which entry will be
    # returned by getpwuid() is not specified.
    passwd = Hash.new {[]}
    # on MacOSX, same entries are returned from /etc/passwd and Open
    # Directory.
    Etc.passwd {|s| passwd[s.uid] |= [s]}
    passwd.each_pair do |uid, s|
      assert_include(s, Etc.getpwuid(uid))
    end
    s = passwd[Process.euid]
    unless s.empty?
      assert_include(s, Etc.getpwuid)
    end
  end

  def test_getpwnam
    passwd = {}
    Etc.passwd do |s|
      passwd[s.name] ||= s unless /\A\+/ =~ s.name
    end
    passwd.each_value do |s|
      assert_equal(s, Etc.getpwnam(s.name))
    end
  end

  def test_passwd_with_low_level_api
    a = []
    Etc.passwd {|s| a << s }
    b = []
    Etc.setpwent
    while s = Etc.getpwent
      b << s
    end
    Etc.endpwent
    assert_equal(a, b)
  end

  def test_group
    Etc.group do |s|
      assert_instance_of(String, s.name)
      assert_instance_of(String, s.passwd) if s.respond_to?(:passwd)
      assert_kind_of(Integer, s.gid)
    end

    Etc.group { assert_raise(RuntimeError) { Etc.group { } }; break }
  end

  def test_getgrgid
    # group database is not unique on GID, and which entry will be
    # returned by getgrgid() is not specified.
    groups = Hash.new {[]}
    # on MacOSX, same entries are returned from /etc/group and Open
    # Directory.
    Etc.group {|s| groups[s.gid] |= [s]}
    groups.each_pair do |gid, s|
      assert_include(s, Etc.getgrgid(gid))
    end
    s = groups[Process.egid]
    unless s.empty?
      assert_include(s, Etc.getgrgid)
    end
  end

  def test_getgrnam
    groups = {}
    Etc.group do |s|
      groups[s.name] ||= s unless /\A\+/ =~ s.name
    end
    groups.each_value do |s|
      assert_equal(s, Etc.getgrnam(s.name))
    end
  end

  def test_group_with_low_level_api
    a = []
    Etc.group {|s| a << s }
    b = []
    Etc.setgrent
    while s = Etc.getgrent
      b << s
    end
    Etc.endgrent
    assert_equal(a, b)
  end
end
