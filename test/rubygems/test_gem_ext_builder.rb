require 'rubygems/test_case'
require 'rubygems/ext'

class TestGemExtBuilder < Gem::TestCase

  def setup
    super

    @ext = File.join @tempdir, 'ext'
    @dest_path = File.join @tempdir, 'prefix'

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path

    @orig_DESTDIR = ENV['DESTDIR']
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

end

