# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestConfig < OpenSSL::TestCase
  def setup
    super
    file = Tempfile.open("openssl.cnf")
    file << <<__EOD__
HOME = .
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = ./demoCA
certs                =                  ./certs
__EOD__
    file.close
    @tmpfile = file
    @it = OpenSSL::Config.new(file.path)
  end

  def teardown
    super
    @tmpfile.close!
  end

  def test_constants
    assert(defined?(OpenSSL::Config::DEFAULT_CONFIG_FILE))
    config_file = OpenSSL::Config::DEFAULT_CONFIG_FILE
    pend "DEFAULT_CONFIG_FILE may return a wrong path on your platforms. [Bug #6830]" unless File.readable?(config_file)
    assert_nothing_raised do
      OpenSSL::Config.load(config_file)
    end
  end

  def test_s_parse
    c = OpenSSL::Config.parse('')
    assert_equal("[ default ]\n\n", c.to_s)
    c = OpenSSL::Config.parse(@it.to_s)
    assert_equal(['CA_default', 'ca', 'default'], c.sections.sort)
  end

  def test_s_parse_format
    c = OpenSSL::Config.parse(<<__EOC__)
 baz =qx\t                # "baz = qx"

foo::bar = baz            # shortcut section::key format
  default::bar = baz      # ditto
a=\t \t                   # "a = ": trailing spaces are ignored
 =b                       # " = b": empty key
 =c                       # " = c": empty key (override the above line)
    d=                    # "c = ": trailing comment is ignored

sq = 'foo''b\\'ar'
    dq ="foo""''\\""
    dq2 = foo""bar
esc=a\\r\\n\\b\\tb
foo\\bar = foo\\b\\\\ar
foo\\bar::foo\\bar = baz
[default1  default2]\t\t  # space is allowed in section name
          fo =b  ar       # space allowed in value
[emptysection]
 [dollar ]
foo=bar
bar = $(foo)
baz = 123$(default::bar)456${foo}798
qux = ${baz}
quxx = $qux.$qux
__EOC__
    assert_equal(['default', 'default1  default2', 'dollar', 'emptysection', 'foo', 'foo\\bar'], c.sections.sort)
    assert_equal(['', 'a', 'bar', 'baz', 'd', 'dq', 'dq2', 'esc', 'foo\\bar', 'sq'], c['default'].keys.sort)
    assert_equal('c', c['default'][''])
    assert_equal('', c['default']['a'])
    assert_equal('qx', c['default']['baz'])
    assert_equal('', c['default']['d'])
    assert_equal('baz', c['default']['bar'])
    assert_equal("foob'ar", c['default']['sq'])
    assert_equal("foo''\"", c['default']['dq'])
    assert_equal("foobar", c['default']['dq2'])
    assert_equal("a\r\n\b\tb", c['default']['esc'])
    assert_equal("foo\b\\ar", c['default']['foo\\bar'])
    assert_equal('baz', c['foo']['bar'])
    assert_equal('baz', c['foo\\bar']['foo\\bar'])
    assert_equal('b  ar', c['default1  default2']['fo'])

    # dollar
    assert_equal('bar', c['dollar']['foo'])
    assert_equal('bar', c['dollar']['bar'])
    assert_equal('123baz456bar798', c['dollar']['baz'])
    assert_equal('123baz456bar798', c['dollar']['qux'])
    assert_equal('123baz456bar798.123baz456bar798', c['dollar']['quxx'])

    excn = assert_raise(OpenSSL::ConfigError) do
      OpenSSL::Config.parse("foo = $bar")
    end
    assert_equal("error in line 1: variable has no value", excn.message)

    excn = assert_raise(OpenSSL::ConfigError) do
      OpenSSL::Config.parse("foo = $(bar")
    end
    assert_equal("error in line 1: no close brace", excn.message)

    excn = assert_raise(OpenSSL::ConfigError) do
      OpenSSL::Config.parse("f o =b  ar      # no space in key")
    end
    assert_equal("error in line 1: missing equal sign", excn.message)

    excn = assert_raise(OpenSSL::ConfigError) do
      OpenSSL::Config.parse(<<__EOC__)
# comment 1               # comments

#
 # comment 2
\t#comment 3
  [second    ]\t
[third                    # section not terminated
__EOC__
    end
    assert_equal("error in line 7: missing close square bracket", excn.message)
  end

  def test_s_parse_include
    if !openssl?(1, 1, 1, 2)
      # OpenSSL < 1.1.1 parses .include directive as a normal assignment
      pend ".include directive is not supported"
    end

    in_tmpdir("ossl-config-include-test") do |dir|
      Dir.mkdir("child")
      File.write("child/a.conf", <<~__EOC__)
        [default]
        file-a = a.conf
        [sec-a]
        a = 123
      __EOC__
      File.write("child/b.cnf", <<~__EOC__)
        [default]
        file-b = b.cnf
        [sec-b]
        b = 123
      __EOC__
      File.write("include-child.conf", <<~__EOC__)
        key_outside_section = value_a
        .include child
      __EOC__

      include_file = <<~__EOC__
        [default]
        file-main = unnamed
        [sec-main]
        main = 123
        .include = include-child.conf
      __EOC__

      # Include a file by relative path
      c1 = OpenSSL::Config.parse(include_file)
      assert_equal(["default", "sec-a", "sec-b", "sec-main"], c1.sections.sort)
      assert_equal(["file-a", "file-b", "file-main"], c1["default"].keys.sort)
      assert_equal({"a" => "123"}, c1["sec-a"])
      assert_equal({"b" => "123"}, c1["sec-b"])
      assert_equal({"main" => "123", "key_outside_section" => "value_a"}, c1["sec-main"])

      # Relative paths are from the working directory
      # Inclusion fails, but the error is ignored silently
      c2 = Dir.chdir("child") { OpenSSL::Config.parse(include_file) }
      assert_equal(["default", "sec-main"], c2.sections.sort)
    end
  end

  def test_s_load
    # alias of new
    c = OpenSSL::Config.load
    assert_equal("", c.to_s)
    assert_equal([], c.sections)
    #
    Tempfile.create("openssl.cnf") {|file|
      file.close
      c = OpenSSL::Config.load(file.path)
      assert_equal("[ default ]\n\n", c.to_s)
      assert_equal(['default'], c.sections)
    }
  end

  def test_s_parse_config
    ret = OpenSSL::Config.parse_config(@it.to_s)
    assert_equal(@it.sections.sort, ret.keys.sort)
    assert_equal(@it["default"], ret["default"])
  end

  def test_initialize
    c = OpenSSL::Config.new
    assert_equal("", c.to_s)
    assert_equal([], c.sections)
  end

  def test_initialize_with_empty_file
    Tempfile.create("openssl.cnf") {|file|
      file.close
      c = OpenSSL::Config.new(file.path)
      assert_equal("[ default ]\n\n", c.to_s)
      assert_equal(['default'], c.sections)
    }
  end

  def test_initialize_with_example_file
    assert_equal(['CA_default', 'ca', 'default'], @it.sections.sort)
  end

  def test_get_value
    assert_equal('CA_default', @it.get_value('ca', 'default_ca'))
    assert_equal(nil, @it.get_value('ca', 'no such key'))
    assert_equal(nil, @it.get_value('no such section', 'no such key'))
    assert_equal('.', @it.get_value('', 'HOME'))
    assert_raise(TypeError) do
      @it.get_value(nil, 'HOME') # not allowed unlike Config#value
    end
    # fallback to 'default' ugly...
    assert_equal('.', @it.get_value('unknown', 'HOME'))
  end

  def test_get_value_ENV
    # LibreSSL removed support for NCONF_get_string(conf, "ENV", str)
    return if libressl?

    key = ENV.keys.first
    assert_not_nil(key) # make sure we have at least one ENV var.
    assert_equal(ENV[key], @it.get_value('ENV', key))
  end

  def test_aref
    assert_equal({'HOME' => '.'}, @it['default'])
    assert_equal({'dir' => './demoCA', 'certs' => './certs'}, @it['CA_default'])
    assert_equal({}, @it['no_such_section'])
    assert_equal({}, @it[''])
  end

  def test_sections
    assert_equal(['CA_default', 'ca', 'default'], @it.sections.sort)
    Tempfile.create("openssl.cnf") { |f|
      f.write File.read(@tmpfile.path)
      f.puts "[ new_section ]"
      f.puts "foo = bar"
      f.puts "[ empty_section ]"
      f.close

      c = OpenSSL::Config.new(f.path)
      assert_equal(['CA_default', 'ca', 'default', 'empty_section', 'new_section'],
                   c.sections.sort)
    }
  end

  def test_each
    # each returns [section, key, value] array.
    ary = @it.map { |e| e }.sort { |a, b| a[0] <=> b[0] }
    assert_equal(4, ary.size)
    assert_equal('CA_default', ary[0][0])
    assert_equal('CA_default', ary[1][0])
    assert_equal(["ca", "default_ca", "CA_default"], ary[2])
    assert_equal(["default", "HOME", "."], ary[3])
  end

  def test_to_s
    c = OpenSSL::Config.parse("[empty]\n")
    assert_equal("[ default ]\n\n[ empty ]\n\n", c.to_s)
  end

  def test_inspect
    assert_match(/#<OpenSSL::Config sections=\[.*\]>/, @it.inspect)
  end

  def test_dup
    assert_equal(['CA_default', 'ca', 'default'], @it.sections.sort)
    c1 = @it.dup
    assert_equal(@it.sections.sort, c1.sections.sort)
    c2 = @it.clone
    assert_equal(@it.sections.sort, c2.sections.sort)
  end

  private

  def in_tmpdir(*args)
    Dir.mktmpdir(*args) do |dir|
      dir = File.realpath(dir)
      Dir.chdir(dir) do
        yield dir
      end
    end
  end
end

end
