require 'rubygems'
require 'minitest/unit'
require 'rdoc/generator'
require 'rdoc/stats'
require 'rdoc/code_objects'
require 'rdoc/markup/to_html_crossref'
require 'rdoc/parser/ruby'

require 'pathname'

class TestRDocMarkupToHtmlCrossref < MiniTest::Unit::TestCase

  #
  # This method parses a source file and returns a Hash mapping
  # class names (Strings) to RDoc::Generator::Class instances
  # (classes), which can be used to create RDoc::Markup::ToHtmlCrossref
  # instances.  The unit tests only test against classes starting with
  # Ref_, so this method only includes such classes in the Hash.
  #
  def create_class_hash
    # The relative gem would help here...
    # @source_file_name must be cleaned because rdoc does not deal
    # well with paths containing "." or "..".
    curr_file = Pathname.new(__FILE__)
    @source_file_name = curr_file.dirname + "rdoc_markup_to_html_crossref_reference.rb"
    @source_file_name = @source_file_name.cleanpath.to_s

    RDoc::TopLevel.reset

    # Reset RDoc::Generator::Method so that the method sequence number starts
    # at 1, making the method sequence numbers for the methods in the Ref_
    # predicable.
    RDoc::Generator::Method.reset
    top_level = RDoc::TopLevel.new @source_file_name

    options = RDoc::Options.new
    options.quiet = true

    # If this is false, then RDoc::Generator::Method will attempt to create
    # an HTML file containing the method source code when being instantiated,
    # which does not work in the context of this unit test.
    #
    # RDoc::Generator::Method needs to be refactored so that this does *not*
    # happen as part of instantiation.
    options.inline_source = true

    stats = RDoc::Stats.new 0

    parser = RDoc::Parser::Ruby.new(top_level,
                                    @source_file_name,
                                    IO.read(@source_file_name),
                                    options,
                                    stats)
    top_levels = []
    top_levels.push(parser.scan())

    files, classes = RDoc::Generator::Context.build_indices(top_levels, options)

    class_hash = {}
    classes.each do |klass|
      if(klass.name.include?("Ref_"))
        class_hash[klass.name] = klass
      end
    end

    return class_hash
  end

  #
  # This method uses xref to cross-reference String reference and
  # asserts that xref.convert(reference) is equal
  # to String expected_result.
  #
  def verify_convert(xref, reference, expected_result)
    # Everything converted in the tests will be within paragraph markup, so
    # add paragraph markup to the expected result.
    actual_expected_result = "<p>\n#{expected_result}\n</p>\n"

    result = xref.convert(reference)

    # RDoc::Markup::ToHtml word-wraps lines.  It is tricky to predict where
    # a line will be wrapped except that it will happen on a space, so replace
    # all newlines with spaces in order to not have to worry about this.
    actual_expected_result.gsub!(/\n/, " ")
    result.gsub!(/\n/, " ")

    assert_equal actual_expected_result, result
  end

  #
  # This method verifies that xref generates no cross-reference link for
  # String reference.
  #
  def verify_no_crossref(xref, reference)
    if(reference[0, 1] == "\\") # Remove the markup suppression character
      expected_result = reference[1, reference.length() - 1]
    else
      expected_result = reference
    end

    verify_convert(xref, reference, expected_result)
  end

  #
  # This method verifies that xref generates a cross-reference link to
  # class_name (String) for String reference.
  #
  def verify_class_crossref(xref, reference, class_name)
    class_file_name = class_name.gsub(/::/, "/")

    result = "<a href=\"../classes/#{class_file_name}.html\">#{reference}</a>"

    verify_convert xref, reference, result
  end

  #
  # This method verifies that xref generates a cross-reference link to method
  # method_seq (String, e.g, "M000001") in class_name (String) for
  # String reference.
  #
  def verify_method_crossref(xref, reference, class_name, method_seq)
    class_file_name = class_name.gsub(/::/, "/")

    result = "<a href=\"../classes/#{class_file_name}.html##{method_seq}\">#{reference}</a>"

    verify_convert xref, reference, result
  end

  #
  # This method verifies that xref generates a cross-reference link to
  # file_name (String) for String reference.
  #
  def verify_file_crossref(xref, reference, file_name)
    generated_document_path = Pathname.new("../files/#{file_name.gsub(/\./, '_')}.html").cleanpath.to_s
    result = "<a href=\"#{generated_document_path}\">#{reference}</a>"

    verify_convert xref, reference, result
  end

  #
  # This method verifies that several invariant cross-references are
  # (or are not) generated.
  #
  def verify_invariant_crossrefs(xref)
    # bogus does not exist and so no cross-reference should be generated.
    verify_no_crossref xref, "bogus"
    verify_no_crossref xref, "\\bogus"

    # Ref_Class1 is in the top-level namespace, and so a cross-reference always
    # should be generated, unless markup is suppressed.
    verify_class_crossref xref, "Ref_Class1", "Ref_Class1"
    verify_no_crossref xref, "\\Ref_Class1"

    # Ref_Class2 is in the top-level namespace, and so a cross-reference always
    # should be generated for it and for its nested classes.
    verify_class_crossref xref, "Ref_Class2", "Ref_Class2"
    verify_class_crossref xref, "Ref_Class2::Ref_Class3", "Ref_Class2::Ref_Class3"
    verify_method_crossref xref, "Ref_Class2::Ref_Class3#method", "Ref_Class2::Ref_Class3", "M000001"
    verify_method_crossref xref, "Ref_Class2::Ref_Class3#method()", "Ref_Class2::Ref_Class3", "M000001"
    verify_method_crossref xref, "Ref_Class2::Ref_Class3.method()", "Ref_Class2::Ref_Class3", "M000001"
    verify_method_crossref xref, "Ref_Class2::Ref_Class3.method(*)", "Ref_Class2::Ref_Class3", "M000001"
    verify_class_crossref xref, "Ref_Class2::Ref_Class3::Helper1", "Ref_Class2::Ref_Class3::Helper1"
    verify_method_crossref xref, "Ref_Class2::Ref_Class3::Helper1#method?", "Ref_Class2::Ref_Class3::Helper1", "M000002"

    # The hyphen character is not a valid class/method separator character, so
    # rdoc just generates a class cross-reference (perhaps it should not
    # generate anything?).
    result = "<a href=\"../classes/Ref_Class2/Ref_Class3.html\">Ref_Class2::Ref_Class3</a>;method(*)"
    verify_convert xref, "Ref_Class2::Ref_Class3;method(*)", result

    # There is one Ref_Class3 nested in Ref_Class2 and one defined in the
    # top-level namespace; regardless, ::Ref_Class3 (Ref_Class3 relative
    # to the top-level namespace) always should generate a link to the
    # top-level Ref_Class3 (unless of course cross-references are suppressed).
    verify_class_crossref xref, "::Ref_Class3", "Ref_Class3"
    verify_no_crossref xref, "\\::Ref_Class3"
    verify_class_crossref xref, "::Ref_Class3::Helper1", "Ref_Class3::Helper1"
    verify_class_crossref xref, "::Ref_Class3::Helper2", "Ref_Class3::Helper2"

    #
    # Ref_Class3::Helper1 does not have method method.
    #
    verify_no_crossref xref, "::Ref_Class3::Helper1#method"
    verify_no_crossref xref, "\\::Ref_Class3::Helper1#method"

    # References to Ref_Class2 relative to the top-level namespace always should
    # generate links to Ref_Class2.
    verify_method_crossref xref, "::Ref_Class2::Ref_Class3#method", "Ref_Class2::Ref_Class3", "M000001"
    verify_method_crossref xref, "::Ref_Class2::Ref_Class3#method()", "Ref_Class2::Ref_Class3", "M000001"
    verify_method_crossref xref, "::Ref_Class2::Ref_Class3#method(*)", "Ref_Class2::Ref_Class3", "M000001"
    verify_class_crossref xref, "::Ref_Class2::Ref_Class3::Helper1", "Ref_Class2::Ref_Class3::Helper1"
    verify_no_crossref xref, "\\::Ref_Class2::Ref_Class3#method(*)"

    # Suppressing cross-references always should suppress the generation of
    # links.
    verify_no_crossref xref, "\\#method"
    verify_no_crossref xref, "\\#method()"
    verify_no_crossref xref, "\\#method(*)"

    # Links never should be generated for words solely consisting of lowercase
    # letters, because too many links would get generated by mistake (i.e., the
    # word "new" always would be a link).
    verify_no_crossref xref, "method"

    # A link always should be generated for a file name.
    verify_file_crossref xref, @source_file_name, @source_file_name

    # References should be generated correctly for a class scoped within
    # a class of the same name.
    verify_class_crossref xref, "Ref_Class4::Ref_Class4", "Ref_Class4::Ref_Class4"
  end

  def test_handle_special_CROSSREF_no_underscore
    class_hash = create_class_hash

    # Note that we instruct the ToHtmlCrossref instance to show hashes so that
    # an exception won't have to be made for words starting with a '#'.
    # I'm also not convinced that the current behavior of the rdoc code
    # is correct since, without this, it strips the leading # from all
    # words, whether or not they end up as cross-references.
    #
    # After the behavior has been sorted out, this can be changed.
    #
    # Create a variety of RDoc::Markup::ToHtmlCrossref instances, for
    # different classes, and test the cross-references generated by
    # each.
    klass = class_hash["Ref_Class1"]
    xref = RDoc::Markup::ToHtmlCrossref.new 'from_path', klass, true
    verify_invariant_crossrefs xref
    verify_class_crossref xref, "Ref_Class3", "Ref_Class3"
    verify_no_crossref xref, "Ref_Class3#method"
    verify_no_crossref xref, "#method"
    verify_class_crossref xref, "Ref_Class3::Helper1", "Ref_Class3::Helper1"
    verify_class_crossref xref, "Ref_Class3::Helper2", "Ref_Class3::Helper2"
    verify_no_crossref xref, "Helper1"
    verify_class_crossref xref, "Ref_Class4", "Ref_Class4"

    klass = class_hash["Ref_Class2"]
    xref = RDoc::Markup::ToHtmlCrossref.new 'from_path', klass, true
    verify_invariant_crossrefs xref
    verify_class_crossref xref, "Ref_Class3", "Ref_Class2::Ref_Class3"
    verify_method_crossref xref, "Ref_Class3#method", "Ref_Class2::Ref_Class3", "M000001"
    verify_no_crossref xref, "#method"
    verify_class_crossref xref, "Ref_Class3::Helper1", "Ref_Class2::Ref_Class3::Helper1"
    verify_class_crossref xref, "Ref_Class4", "Ref_Class4"

    # This one possibly is an rdoc bug...
    # Ref_Class2 has a nested Ref_Class3, but
    # Ref_Class2::Ref_Class3::Helper2 does not exist.
    # On the other hand, there is a Ref_Class3::Helper2
    # in the top-level namespace...  Should rdoc stop
    # looking if it finds one class match?
    verify_no_crossref xref, "Ref_Class3::Helper2"
    verify_no_crossref xref, "Helper1"

    klass = class_hash["Ref_Class2::Ref_Class3"]
    xref = RDoc::Markup::ToHtmlCrossref.new 'from_path', klass, true
    verify_invariant_crossrefs xref
    verify_class_crossref xref, "Ref_Class3", "Ref_Class2::Ref_Class3"
    verify_method_crossref xref, "Ref_Class3#method", "Ref_Class2::Ref_Class3", "M000001"
    verify_method_crossref xref, "#method", "Ref_Class2::Ref_Class3", "M000001"
    verify_class_crossref xref, "Ref_Class3::Helper1", "Ref_Class2::Ref_Class3::Helper1"
    verify_no_crossref xref, "Ref_Class3::Helper2"
    verify_class_crossref xref, "Helper1", "Ref_Class2::Ref_Class3::Helper1"
    verify_class_crossref xref, "Ref_Class4", "Ref_Class4"

    klass = class_hash["Ref_Class3"]
    xref = RDoc::Markup::ToHtmlCrossref.new 'from_path', klass, true
    verify_invariant_crossrefs xref
    verify_class_crossref xref, "Ref_Class3", "Ref_Class3"
    verify_no_crossref xref, "Ref_Class3#method"
    verify_no_crossref xref, "#method"
    verify_class_crossref xref, "Ref_Class3::Helper1", "Ref_Class3::Helper1"
    verify_class_crossref xref, "Ref_Class3::Helper2", "Ref_Class3::Helper2"
    verify_class_crossref xref, "Helper1", "Ref_Class3::Helper1"
    verify_class_crossref xref, "Ref_Class4", "Ref_Class4"

    klass = class_hash["Ref_Class4"]
    xref = RDoc::Markup::ToHtmlCrossref.new 'from_path', klass, true
    verify_invariant_crossrefs xref
    # A Ref_Class4 reference inside a Ref_Class4 class containing a
    # Ref_Class4 class should resolve to the contained class.
    verify_class_crossref xref, "Ref_Class4", "Ref_Class4::Ref_Class4"

    klass = class_hash["Ref_Class4::Ref_Class4"]
    xref = RDoc::Markup::ToHtmlCrossref.new 'from_path', klass, true
    verify_invariant_crossrefs xref
    # A Ref_Class4 reference inside a Ref_Class4 class contained within
    # a Ref_Class4 class should resolve to the inner Ref_Class4 class.
    verify_class_crossref xref, "Ref_Class4", "Ref_Class4::Ref_Class4"
  end
end

MiniTest::Unit.autorun
