require 'rubygems'
require 'minitest/unit'
require 'tmpdir'
require 'rdoc/ri/driver'

class TestRDocRIDriver < MiniTest::Unit::TestCase

  def setup
    @tmpdir = File.join Dir.tmpdir, "test_rdoc_ri_driver_#{$$}"
    @home_ri = File.join @tmpdir, 'dot_ri'
    @cache_dir = File.join @home_ri, 'cache'
    @class_cache = File.join @cache_dir, 'classes'

    FileUtils.mkdir_p @tmpdir
    FileUtils.mkdir_p @home_ri
    FileUtils.mkdir_p @cache_dir

    @driver = RDoc::RI::Driver.new(RDoc::RI::Driver.process_args([]))
    @driver.homepath = @home_ri
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_lookup_method
    def @driver.load_cache_for(klassname)
      { 'Foo#bar' => :found }
    end

    assert @driver.lookup_method('Foo#bar',  'Foo')
  end

  def test_lookup_method_class_method
    def @driver.load_cache_for(klassname)
      { 'Foo::Bar' => :found }
    end

    assert @driver.lookup_method('Foo::Bar', 'Foo::Bar')
  end

  def test_lookup_method_class_missing
    def @driver.load_cache_for(klassname) end

    assert_nil @driver.lookup_method('Foo#bar', 'Foo')
  end

  def test_lookup_method_dot_instance
    def @driver.load_cache_for(klassname)
      { 'Foo#bar' => :instance, 'Foo::bar' => :klass }
    end

    assert_equal :instance, @driver.lookup_method('Foo.bar', 'Foo')
  end

  def test_lookup_method_dot_class
    def @driver.load_cache_for(klassname)
      { 'Foo::bar' => :found }
    end

    assert @driver.lookup_method('Foo.bar', 'Foo')
  end

  def test_lookup_method_method_missing
    def @driver.load_cache_for(klassname) {} end

    assert_nil @driver.lookup_method('Foo#bar', 'Foo')
  end

  def test_parse_name
    klass, meth = @driver.parse_name 'Foo::Bar'

    assert_equal 'Foo::Bar', klass, 'Foo::Bar class'
    assert_equal nil,        meth,  'Foo::Bar method'

    klass, meth = @driver.parse_name 'Foo#Bar'

    assert_equal 'Foo', klass, 'Foo#Bar class'
    assert_equal 'Bar', meth,  'Foo#Bar method'

    klass, meth = @driver.parse_name 'Foo.Bar'

    assert_equal 'Foo', klass, 'Foo#Bar class'
    assert_equal 'Bar', meth,  'Foo#Bar method'

    klass, meth = @driver.parse_name 'Foo::bar'

    assert_equal 'Foo', klass, 'Foo::bar class'
    assert_equal 'bar', meth,  'Foo::bar method'
  end

end

MiniTest::Unit.autorun
