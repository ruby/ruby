require 'rubygems/test_case'
require 'rubygems/ext'
require 'rubygems/installer'

class TestGemExtBuilder < Gem::TestCase

  def setup
    super

    @ext = File.join @tempdir, 'ext'
    @dest_path = File.join @tempdir, 'prefix'

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path

    @orig_DESTDIR = ENV['DESTDIR']

    @spec = quick_spec 'a'

    @builder = Gem::Ext::Builder.new @spec, ''
  end

  def teardown
    ENV['DESTDIR'] = @orig_DESTDIR

    super
  end

  def test_class_make
    ENV['DESTDIR'] = 'destination'
    results = []

    Dir.chdir @ext do
      open 'Makefile', 'w' do |io|
        io.puts <<-MAKEFILE
all:
\t@#{Gem.ruby} -e "puts %Q{all: \#{ENV['DESTDIR']}}"

install:
\t@#{Gem.ruby} -e "puts %Q{install: \#{ENV['DESTDIR']}}"
        MAKEFILE
      end

      Gem::Ext::Builder.make @dest_path, results
    end

    results = results.join "\n"


    if RUBY_VERSION > '2.0' then
      assert_match %r%"DESTDIR=#{ENV['DESTDIR']}"$%,         results
      assert_match %r%"DESTDIR=#{ENV['DESTDIR']}" install$%, results
    else
      refute_match %r%"DESTDIR=#{ENV['DESTDIR']}"$%,         results
      refute_match %r%"DESTDIR=#{ENV['DESTDIR']}" install$%, results
    end

    if /nmake/ !~ results
      assert_match %r%^all: destination$%,     results
      assert_match %r%^install: destination$%, results
    end
  end

  def test_build_extensions_none
    use_ui @ui do
      @builder.build_extensions
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    refute File.exist?('gem_make.out')
  end

  def test_build_extensions_extconf_bad
    @spec.extensions << 'extconf.rb'

    e = assert_raises Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @builder.build_extensions
      end
    end

    assert_match(/\AERROR: Failed to build gem native extension.$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    gem_make_out = File.join @gemhome, 'gems', @spec.full_name, 'gem_make.out'

    assert_match %r%#{Regexp.escape Gem.ruby} extconf\.rb%,
                 File.read(gem_make_out)
    assert_match %r%#{Regexp.escape Gem.ruby}: No such file%,
                 File.read(gem_make_out)
  end

  def test_build_extensions_unsupported
    FileUtils.mkdir_p @spec.gem_dir
    gem_make_out = File.join @spec.gem_dir, 'gem_make.out'
    @spec.extensions << nil

    e = assert_raises Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @builder.build_extensions
      end
    end

    assert_match(/^\s*No builder for extension ''$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    assert_equal "No builder for extension ''\n", File.read(gem_make_out)
  ensure
    FileUtils.rm_f gem_make_out
  end

  def test_build_extensions_with_build_args
    args = ["--aa", "--bb"]
    @builder.build_args = args
    @spec.extensions << 'extconf.rb'

    FileUtils.mkdir_p @spec.gem_dir

    open File.join(@spec.gem_dir, "extconf.rb"), "w" do |f|
      f.write <<-'RUBY'
        puts "IN EXTCONF"
        extconf_args = File.join File.dirname(__FILE__), 'extconf_args'
        File.open extconf_args, 'w' do |f|
          f.puts ARGV.inspect
        end

        File.open 'Makefile', 'w' do |f|
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    use_ui @ui do
      @builder.build_extensions
    end

    path = File.join @spec.gem_dir, "extconf_args"

    assert_equal args.inspect, File.read(path).strip
    assert File.directory? File.join(@spec.gem_dir, 'lib')
  end

end

