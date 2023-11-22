require 'bundler/errors'
begin
  gem 'test-unit'
rescue NoMethodError, Gem::LoadError, Bundler::GemfileNotFound
  # for ruby tests
end

require 'test/unit'

require 'fileutils'
require 'pp'
require 'tempfile'
require 'tmpdir'
require 'stringio'

require_relative '../../../lib/rdoc'

##
# RDoc::TestCase is an abstract TestCase to provide common setup and teardown
# across all RDoc tests.  The test case uses test-unit, so all the assertions
# of test-unit may be used.
#
# The testcase provides the following:
#
# * A reset code-object tree
# * A reset markup preprocessor (RDoc::Markup::PreProcess)
# * The <code>@RM</code> alias of RDoc::Markup (for less typing)
# * <code>@pwd</code> containing the current working directory
# * FileUtils, pp, Tempfile, Dir.tmpdir and StringIO

class RDoc::TestCase < Test::Unit::TestCase

  ##
  # Abstract test-case setup

  def setup
    super

    @orig_home = ENV["HOME"]
    FileUtils.mkdir_p(@test_home = Dir.mktmpdir("test_rdoc_"))
    ENV["HOME"] = @test_home

    @top_level = nil

    @RM = RDoc::Markup

    @pwd = Dir.pwd

    @store = RDoc::Store.new

    @rdoc = RDoc::RDoc.new
    @rdoc.store = @store
    @rdoc.options = RDoc::Options.new

    g = Object.new
    def g.class_dir() end
    def g.file_dir() end
    @rdoc.generator = g

    RDoc::Markup::PreProcess.reset
  end

  ##
  # Abstract test-case teardown

  def teardown
    ENV["HOME"] = @orig_home if defined?(@orig_home)
    defined?(@test_home) and FileUtils.rm_rf @test_home

    super
  end

  ##
  # Asserts +path+ is a file

  def assert_file path
    assert File.file?(path), "#{path} is not a file"
  end

  ##
  # Asserts +path+ is a directory

  def assert_directory path
    assert File.directory?(path), "#{path} is not a directory"
  end

  ##
  # Refutes +path+ exists

  def refute_file path
    refute File.exist?(path), "#{path} exists"
  end

  ##
  # Shortcut for RDoc::Markup::BlankLine.new

  def blank_line
    @RM::BlankLine.new
  end

  ##
  # Shortcut for RDoc::Markup::BlockQuote.new with +contents+

  def block *contents
    @RM::BlockQuote.new(*contents)
  end

  ##
  # Creates an RDoc::Comment with +text+ which was defined on +top_level+.
  # By default the comment has the 'rdoc' format.

  def comment text, top_level = @top_level, language = nil
    comment = RDoc::Comment.new text, top_level, language
    comment
  end

  ##
  # Shortcut for RDoc::Markup::Document.new with +contents+

  def doc *contents
    @RM::Document.new(*contents)
  end

  ##
  # Shortcut for RDoc::Markup::HardBreak.new

  def hard_break
    @RM::HardBreak.new
  end

  ##
  # Shortcut for RDoc::Markup::Heading.new with +level+ and +text+

  def head level, text
    @RM::Heading.new level, text
  end

  ##
  # Shortcut for RDoc::Markup::ListItem.new with +label+ and +parts+

  def item label = nil, *parts
    @RM::ListItem.new label, *parts
  end

  ##
  # Shortcut for RDoc::Markup::List.new with +type+ and +items+

  def list type = nil, *items
    @RM::List.new type, *items
  end

  ##
  # Enables pretty-print output

  def mu_pp obj # :nodoc:
    s = obj.pretty_inspect
    s = RDoc::Encoding.change_encoding s, Encoding.default_external
    s.chomp
  end

  ##
  # Shortcut for RDoc::Markup::Paragraph.new with +contents+

  def para *a
    @RM::Paragraph.new(*a)
  end

  ##
  # Shortcut for RDoc::Markup::Rule.new with +weight+

  def rule weight
    @RM::Rule.new weight
  end

  ##
  # Shortcut for RDoc::Markup::Raw.new with +contents+

  def raw *contents
    @RM::Raw.new(*contents)
  end

  ##
  # Creates a temporary directory changes the current directory to it for the
  # duration of the block.
  #
  # Depends upon Dir.mktmpdir

  def temp_dir
    Dir.mktmpdir do |temp_dir|
      Dir.chdir temp_dir do
        yield temp_dir
      end
    end
  end

  ##
  # Shortcut for RDoc::Markup::Verbatim.new with +parts+

  def verb *parts
    @RM::Verbatim.new(*parts)
  end

  ##
  # run capture_io with setting $VERBOSE = true

  def verbose_capture_output
    capture_output do
      begin
        orig_verbose = $VERBOSE
        $VERBOSE = true
        yield
      ensure
        $VERBOSE = orig_verbose
      end
    end
  end
end
