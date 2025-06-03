# frozen_string_literal: true
require "test/unit"
require "etc"

class TestEtc < Test::Unit::TestCase
  def test_getlogin
    s = Etc.getlogin
    return if s == nil
    assert(s.is_a?(String), "getlogin must return a String or nil")
    assert_predicate(s, :valid_encoding?, "login name should be a valid string")
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
      assert(s.age.is_a?(Integer) || s.age.is_a?(String), s.age) if s.respond_to?(:age)
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
  end unless RUBY_PLATFORM.include?("android")

  def test_getpwnam
    passwd = {}
    Etc.passwd do |s|
      passwd[s.name] ||= s unless /\A\+/ =~ s.name
    end
    passwd.each_value do |s|
      assert_equal(s, Etc.getpwnam(s.name))
    end
  end unless RUBY_PLATFORM.include?("android")

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
    Etc.group {|s| groups[s.gid] |= [[s.name, s.gid]]}
    groups.each_pair do |gid, s|
      g = Etc.getgrgid(gid)
      assert_include(s, [g.name, g.gid])
    end
    s = groups[Process.egid]
    unless s.empty?
      g = Etc.getgrgid
      assert_include(s, [g.name, g.gid])
    end
  end

  def test_getgrnam
    groups = Hash.new {[]}
    Etc.group do |s|
      groups[s.name] |= [s.gid] unless /\A\+/ =~ s.name
    end
    groups.each_pair do |n, s|
      assert_include(s, Etc.getgrnam(n).gid)
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

  def test_uname
    begin
      uname = Etc.uname
    rescue NotImplementedError
      return
    end
    assert_kind_of(Hash, uname)
    [:sysname, :nodename, :release, :version, :machine].each {|sym|
      assert_operator(uname, :has_key?, sym)
      assert_kind_of(String, uname[sym])
    }
  end

  def test_sysconf
    begin
      Etc.sysconf
    rescue NotImplementedError
      return
    rescue ArgumentError
    end
    assert_kind_of(Integer, Etc.sysconf(Etc::SC_CLK_TCK))
  end if defined?(Etc::SC_CLK_TCK)

  def test_confstr
    begin
      Etc.confstr
    rescue NotImplementedError
      return
    rescue ArgumentError
    end
    assert_kind_of(String, Etc.confstr(Etc::CS_PATH))
  end if defined?(Etc::CS_PATH)

  def test_pathconf
    begin
      Etc.confstr
    rescue NotImplementedError
      return
    rescue ArgumentError
    end
    IO.pipe {|r, w|
      val = w.pathconf(Etc::PC_PIPE_BUF)
      assert_kind_of(Integer, val) if val
    }
  end if defined?(Etc::PC_PIPE_BUF)

  def test_nprocessors
    n = Etc.nprocessors
    assert_operator(1, :<=, n)
  end

  def test_sysconfdir
    assert_operator(File, :absolute_path?, Etc.sysconfdir)
  end if File.method_defined?(:absolute_path?)

  # All Ractor-safe methods should be tested here
  def test_ractor_parallel
    omit "This test is flaky and intermittently failing now on ModGC workflow" if ENV['GITHUB_WORKFLOW'] == 'ModGC'

    assert_ractor(<<~RUBY, require: 'etc', timeout: 60)
      class Ractor
        alias join take
      end unless Ractor.method_defined? :value # compat with Ruby 3.4 and olders

      10.times.map do
        Ractor.new do
          100.times do
            raise unless String === Etc.systmpdir
            raise unless Hash === Etc.uname
            if defined?(Etc::SC_CLK_TCK)
              raise unless Integer === Etc.sysconf(Etc::SC_CLK_TCK)
            end
            if defined?(Etc::CS_PATH)
              raise unless String === Etc.confstr(Etc::CS_PATH)
            end
            if defined?(Etc::PC_PIPE_BUF)
              IO.pipe { |r, w|
                val = w.pathconf(Etc::PC_PIPE_BUF)
                raise unless val.nil? || val.kind_of?(Integer)
              }
            end
            raise unless Integer === Etc.nprocessors
          end
        end
      end.each(&:join)
    RUBY
  end

  def test_ractor_unsafe
    assert_ractor(<<~RUBY, require: 'etc')
      class Ractor
        alias value take
      end unless Ractor.method_defined? :value # compat with Ruby 3.4 and olders

      r = Ractor.new do
        begin
          Etc.passwd
        rescue => e
          e.class
        end
      end.value
      assert_equal Ractor::UnsafeError, r
    RUBY
  end

  def test_ractor_passwd
    omit("https://bugs.ruby-lang.org/issues/21115")
    return unless Etc.passwd # => skip test if no platform support
    Etc.endpwent

    assert_ractor(<<~RUBY, require: 'etc')
      ractor = Ractor.new port = Ractor::Port.new do |port|
        Etc.passwd do |s|
          port << :sync
          port << s.name
          break :done
        end
      end
      port.receive # => :sync
      assert_raise RuntimeError, /parallel/ do
        Etc.passwd {}
      end
      name = port.receive # => first name
      ractor.join # => :done
      name2 = Etc.passwd do |s|
        break s.name
      end
      assert_equal(name2, name)
    RUBY
  end

  def test_ractor_getgrgid
    omit("https://bugs.ruby-lang.org/issues/21115")

    assert_ractor(<<~RUBY, require: 'etc')
      20.times.map do
        Ractor.new do
          1000.times do
            raise unless Etc.getgrgid(Process.gid).gid == Process.gid
          end
        end
      end.each(&:join)
    RUBY
  end
end
