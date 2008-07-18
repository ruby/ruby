$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib/'
require 'fileutils'
require 'test/unit'
require 'rdoc/generator/texinfo'
require 'yaml'

# give us access to check this stuff before it's rendered
class RDoc::Generator::Texinfo; attr_reader :files, :classes; end
class RDoc::RDoc; attr_reader :options; attr_reader :gen; end

class TestRdocInfoSections < Test::Unit::TestCase
  OUTPUT_DIR = "/tmp/rdoc-#{$$}"

  def setup
    # supress stdout
    $stdout = File.new('/dev/null','w')
    $stderr = File.new('/dev/null','w')

    @rdoc = RDoc::RDoc.new
    @rdoc.document(['--fmt=texinfo',
                    File.expand_path(File.dirname(__FILE__) + '/../lib/rdoc/generator/texinfo.rb'),
                    File.expand_path(File.dirname(__FILE__) + '/../README.txt'),
                    "--op=#{OUTPUT_DIR}"])
    @text = File.read(OUTPUT_DIR + '/rdoc.texinfo')
  end

  def teardown
    $stdout = STDOUT
    $stderr = STDERR
    FileUtils.rm_rf OUTPUT_DIR
  end

  def test_output_exists
    assert ! @text.empty?
  end

  def test_each_class_has_a_chapter
    assert_section "Class RDoc::Generator::Texinfo", '@chapter'
    assert_section "Class RDoc::Generator::TexinfoTemplate", '@chapter'
  end

  def test_class_descriptions_are_given
    assert_match(/This generates .*Texinfo.* files for viewing with GNU Info or Emacs from .*RDoc.* extracted from Ruby source files/, @text.gsub("\n", ' '))
  end

  def test_included_modules_are_given
    assert_match(/Includes.* Generator::MarkUp/m, @text)
  end

  def test_class_methods_are_given
    assert_match(/new\(options\)/, @text)
  end

  def test_classes_instance_methods_are_given
    assert_section 'Class RDoc::Generator::Texinfo#generate'
    assert_match(/generate\(toplevels\)/, @text)
  end

  def test_each_module_has_a_chapter
    assert_section "RDoc", '@chapter'
    assert_section "Generator", '@chapter'
  end

  def test_methods_are_shown_only_once
    methods = @rdoc.gen.classes.map { |c| c.methods.map{ |m| c.name + '#' + m.name } }.flatten
    assert_equal methods, methods.uniq
  end

#   if system "makeinfo --version > /dev/null"
#     def test_compiles_to_info
#       makeinfo_output = `cd #{OUTPUT_DIR} && makeinfo rdoc.texinfo`
#       assert(File.exist?(File.join(OUTPUT_DIR, 'rdoc.info')),
#              "Info file was not compiled: #{makeinfo_output}")
#     end
#   end

#   def test_constants_are_documented_somehow
#     assert_section 'DEFAULT_FILENAME' # what kind of section?
#     assert_section 'DEFAULT_INFO_FILENAME'
#   end

#   def test_oh_yeah_dont_forget_files
#   end

  private
  def assert_section(name, command = '@section')
    assert_match Regexp.new("^#{command}.*#{Regexp.escape name}"), @text, "Could not find a #{command} #{name}"
  end

#   def puts(*args)
#     @real_stdout.puts(*args)
#   end
end
