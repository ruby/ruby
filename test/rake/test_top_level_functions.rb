require 'test/unit'
require_relative 'capture_stdout'
require 'rake'

class Rake::TestTopLevelFunctions < Test::Unit::TestCase
  include CaptureStdout

  def setup
    super
    @app = Rake.application
    Rake.application = @mock = Object.new
  end

  def teardown
    Rake.application = @app
    super
  end

  def defmock(sym, &block)
    class << @mock; self; end.class_eval do
      define_method(sym, block)
    end
  end

  def test_namespace
    args = []
    defmock(:in_namespace) {|a, *| args << a}
    namespace "xyz" do end
    assert_equal(["xyz"], args)
  end

  def test_import
    args = []
    defmock(:add_import) {|a| args << a}
    import('x', 'y', 'z')
    assert_equal(['x', 'y', 'z'], args)
  end

  def test_when_writing
    out = capture_stdout do
      when_writing("NOTWRITING") do
        puts "WRITING"
      end
    end
    assert_equal "WRITING\n", out
  end

  def test_when_not_writing
    RakeFileUtils.nowrite_flag = true
    out = capture_stdout do
      when_writing("NOTWRITING") do
        puts "WRITING"
      end
    end
    assert_equal "DRYRUN: NOTWRITING\n", out
  ensure
    RakeFileUtils.nowrite_flag = false
  end

  def test_missing_constants_task
    args = []
    defmock(:const_warning) {|a| args << a}
    Object.const_missing(:Task)
    assert_equal([:Task], args)
  end

  def test_missing_constants_file_task
    args = []
    defmock(:const_warning) {|a| args << a}
    Object.const_missing(:FileTask)
    assert_equal([:FileTask], args)
  end

  def test_missing_constants_file_creation_task
    args = []
    defmock(:const_warning) {|a| args << a}
    Object.const_missing(:FileCreationTask)
    assert_equal([:FileCreationTask], args)
  end

  def test_missing_constants_rake_app
    args = []
    defmock(:const_warning) {|a| args << a}
    Object.const_missing(:RakeApp)
    assert_equal([:RakeApp], args)
  end

  def test_missing_other_constant
    assert_raise(NameError) do Object.const_missing(:Xyz) end
  end
end
