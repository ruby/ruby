require 'rake'
require 'test/unit'
require_relative 'filecreation'
require 'fileutils'
require 'stringio'

class Rake::TestFileUtils < Test::Unit::TestCase
  include FileCreation
  BASEDIR = File.dirname(__FILE__)
  ShellCommand =  "#{BASEDIR}/shellcommand.rb"
  ENV_RUBY = ENV['RUBY']

  def setup
    if ruby = ENV_RUBY
      @oldruby = FileUtils.class_eval {remove_const :RUBY}
      FileUtils.class_eval {const_set(:RUBY, ruby)}
    else
      @oldruby = nil
    end
  end

  def teardown
    FileUtils.rm_rf("testdata")
    FileUtils::LN_SUPPORTED[0] = true
    if @oldruby
      ruby = @oldruby
      FileUtils.class_eval {remove_const :RUBY}
      FileUtils.class_eval {const_set(:RUBY, ruby)}
    end
  end

  def test_rm_one_file
    create_file("testdata/a")
    FileUtils.rm_rf "testdata/a"
    assert ! File.exist?("testdata/a")
  end

  def test_rm_two_files
    create_file("testdata/a")
    create_file("testdata/b")
    FileUtils.rm_rf ["testdata/a", "testdata/b"]
    assert ! File.exist?("testdata/a")
    assert ! File.exist?("testdata/b")
  end

  def test_rm_filelist
    list = Rake::FileList.new << "testdata/a" << "testdata/b"
    list.each { |fn| create_file(fn) }
    FileUtils.rm_r list
    assert ! File.exist?("testdata/a")
    assert ! File.exist?("testdata/b")
  end

  def test_ln
    create_dir("testdata")
    open("testdata/a", "w") { |f| f.puts "TEST_LN" }
    RakeFileUtils.safe_ln("testdata/a", "testdata/b", :verbose => false)
    assert_equal "TEST_LN\n", open("testdata/b") { |f| f.read }
  end

  class BadLink
    include RakeFileUtils
    attr_reader :cp_args
    def initialize(klass)
      @failure_class = klass
    end
    def cp(*args)
      @cp_args = args
    end
    def ln(*args)
      fail @failure_class, "ln not supported"
    end
    public :safe_ln
  end

  def test_safe_ln_failover_to_cp_on_standard_error
    FileUtils::LN_SUPPORTED[0] = true
    c = BadLink.new(StandardError)
    c.safe_ln "a", "b"
    assert_equal ['a', 'b'], c.cp_args
    c.safe_ln "x", "y"
    assert_equal ['x', 'y'], c.cp_args
  end

  def test_safe_ln_failover_to_cp_on_not_implemented_error
    FileUtils::LN_SUPPORTED[0] = true
    c = BadLink.new(NotImplementedError)
    c.safe_ln "a", "b"
    assert_equal ['a', 'b'], c.cp_args
  end

  def test_safe_ln_fails_on_script_error
    FileUtils::LN_SUPPORTED[0] = true
    c = BadLink.new(ScriptError)
    assert_raise(ScriptError) do c.safe_ln "a", "b" end
  end

  def test_verbose
    verbose true
    assert_equal true, verbose
    verbose false
    assert_equal false, verbose
    verbose(true) {
      assert_equal true, verbose
    }
    assert_equal false, verbose
  end

  def test_nowrite
    nowrite true
    assert_equal true, nowrite
    nowrite false
    assert_equal false, nowrite
    nowrite(true){
      assert_equal true, nowrite
    }
    assert_equal false, nowrite
  end

  def test_file_utils_methods_are_available_at_top_level
    create_file("testdata/a")
    verbose(false) do
      rm_rf "testdata/a"
    end
    assert ! File.exist?("testdata/a")
  end

  def test_fileutils_methods_dont_leak
    obj = Object.new
    assert_raise(NoMethodError) { obj.copy } # from FileUtils
    assert_raise(NoMethodError) { obj.ruby } # from RubyFileUtils
  end

  def test_sh
    verbose(false) { sh %{#{RUBY} #{ShellCommand}} }
    assert true, "should not fail"
  end

  # If the :sh method is invoked directly from a test unit instance
  # (under mini/test), the mini/test version of fail is invoked rather
  # than the kernel version of fail. So we run :sh from within a
  # non-test class to avoid the problem.
  class Sh
    include FileUtils
    def run(*args)
      sh(*args)
    end
    def self.run(*args)
      new.run(*args)
    end
  end

  def test_sh_with_a_single_string_argument
    ENV['RAKE_TEST_SH'] = 'someval'
    verbose(false) {
      sh %{#{RUBY} #{BASEDIR}/check_expansion.rb #{env_var} someval}
    }
  end

  def test_sh_with_multiple_arguments
    ENV['RAKE_TEST_SH'] = 'someval'
    verbose(false) {
      Sh.run RUBY, File.expand_path('../check_no_expansion.rb', __FILE__), env_var, 'someval'
    }
  end

  def test_sh_failure
    assert_raise(RuntimeError) {
      verbose(false) { Sh.run "#{RUBY} #{File.expand_path('../shellcommand.rb', __FILE__)} 1" }
    }
  end

  def test_sh_special_handling
    count = 0
    verbose(false) {
      sh(%{#{RUBY} #{ShellCommand}}) do |ok, res|
        assert(ok)
        assert_equal 0, res.exitstatus
        count += 1
      end
      sh(%{#{RUBY} #{ShellCommand} 1}) do |ok, res|
        assert(!ok)
        assert_equal 1, res.exitstatus
        count += 1
      end
    }
    assert_equal 2, count, "Block count should be 2"
  end

  def test_sh_noop
    verbose(false) { sh %{#{ShellCommand} 1}, :noop=>true }
    assert true, "should not fail"
  end

  def test_sh_bad_option
    ex = assert_raise(ArgumentError) {
      verbose(false) { sh %{#{ShellCommand}}, :bad_option=>true }
    }
    assert_match(/bad_option/, ex.message)
  end

  def test_sh_verbose
    out = redirect_stderr {
      verbose(true) {
        sh %{#{ShellCommand}}, :noop=>true
      }
    }
    assert_match(/^#{Regexp.quote(ShellCommand)}$/o, out)
  end

  def test_sh_no_verbose
    out = redirect_stderr {
      verbose(false) {
        sh %{#{ShellCommand}}, :noop=>true
      }
    }
    assert_equal '', out
  end

  def test_ruby_with_a_single_string_argument
    ENV['RAKE_TEST_SH'] = 'someval'
    verbose(false) {
      ruby %{#{BASEDIR}/check_expansion.rb #{env_var} someval}
    }
  end

  def test_ruby_with_multiple_arguments
    ENV['RAKE_TEST_SH'] = 'someval'
    verbose(false) {
      ruby "#{BASEDIR}/check_no_expansion.rb", env_var, 'someval'
    }
  end

  def test_split_all
    assert_equal ['a'], RakeFileUtils.split_all('a')
    assert_equal ['..'], RakeFileUtils.split_all('..')
    assert_equal ['/'], RakeFileUtils.split_all('/')
    assert_equal ['a', 'b'], RakeFileUtils.split_all('a/b')
    assert_equal ['/', 'a', 'b'], RakeFileUtils.split_all('/a/b')
    assert_equal ['..', 'a', 'b'], RakeFileUtils.split_all('../a/b')
  end

  private

  def redirect_stderr
    old_err = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old_err
  end

  def windows?
    ! File::ALT_SEPARATOR.nil?
  end

  def env_var
    windows? ? '%RAKE_TEST_SH%' : '$RAKE_TEST_SH'
  end

end
