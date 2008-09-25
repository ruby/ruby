require 'fileutils'
require 'tempfile'
require 'test/unit'
require 'tmpdir'

require 'rdoc/generator/texinfo'

# give us access to check this stuff before it's rendered
class RDoc::Generator::TEXINFO; attr_reader :files, :classes; end
class RDoc::RDoc; attr_reader :options; attr_reader :gen; end

class TestRDocInfoSections < Test::Unit::TestCase

  def setup
    @output_dir = File.join Dir.tmpdir, "test_rdoc_info_sections_#{$$}"
    @output_file = File.join @output_dir, 'rdoc.texinfo'

    @input_file = Tempfile.new 'my_file.rb'

    open @input_file.path, 'w' do |io|
      io.write TEST_DOC
    end

    RDoc::Parser.alias_extension '.rb', File.extname(@input_file.path)

    @rdoc = RDoc::RDoc.new
    @rdoc.document(['--fmt=texinfo', '--quiet', @input_file.path,
                    "--op=#{@output_dir}"])

    @text = File.read @output_file
  end

  def teardown
    @input_file.close
    FileUtils.rm_rf @output_dir
  end

  def test_output_exists
    assert ! @text.empty?
  end

  def test_each_class_has_a_chapter
    assert_section "Class MyClass", '@chapter'
  end

  def test_class_descriptions_are_given
    assert_match(/Documentation for my class/, @text.gsub("\n", ' '))
  end

  def test_included_modules_are_given
    assert_match(/Includes.* MyModule/m, @text)
  end

  def test_class_methods_are_given
    assert_match(/my_class_method\(my_first_argument\)/, @text)
  end

  def test_classes_instance_methods_are_given
    assert_section 'Class MyClass#my_method'
    assert_match(/my_method\(my_first_argument\)/, @text)
  end

  def test_each_module_has_a_chapter
    assert_section 'MyModule', '@chapter'
  end

  def test_methods_are_shown_only_once
    methods = @rdoc.gen.classes.map do |c|
      c.methods.map do |m|
        c.name + '#' + m.name
      end
    end.flatten

    assert_equal methods, methods.uniq
  end

#   if system "makeinfo --version > /dev/null"
#     def test_compiles_to_info
#       makeinfo_output = `cd #{@output_dir} && makeinfo rdoc.texinfo`
#       assert(File.exist?(File.join(@output_dir, 'rdoc.info')),
#              "Info file was not compiled: #{makeinfo_output}")
#     end
#   end

#   def test_constants_are_documented_somehow
#     assert_section 'DEFAULT_FILENAME' # what kind of section?
#     assert_section 'DEFAULT_INFO_FILENAME'
#   end

#   def test_oh_yeah_dont_forget_files
#   end

  def assert_section(name, command = '@section')
    assert_match Regexp.new("^#{command}.*#{Regexp.escape name}"), @text, "Could not find a #{command} #{name}"
  end

  TEST_DOC = <<-DOC
##
# Documentation for my module

module MyModule

  ##
  # Documentation for my included method

  def my_included_method() end

end

##
# Documentation for my class

class MyClass

  include MyModule

  ##
  # Documentation for my constant

  MY_CONSTANT = 'my value'

  ##
  # Documentation for my class method

  def self.my_class_method(my_first_argument) end

  ##
  # Documentation for my method

  def my_method(my_first_argument) end

end

  DOC

end
