$LOAD_PATH.unshift '../../lib'
require 'test/unit'
require "xmlrpc/parser"

module GenericParserTest
  def setup
    @xml1 = File.readlines("data/xml1.xml").to_s
    @expected1 = File.readlines("data/xml1.expected").to_s.chomp

    @xml2 = File.readlines("data/bug_covert.xml").to_s
    @expected2 = File.readlines("data/bug_covert.expected").to_s.chomp

    @xml3 = File.readlines("data/bug_bool.xml").to_s
    @expected3 = File.readlines("data/bug_bool.expected").to_s.chomp

    @xml4 = File.readlines("data/value.xml").to_s
    @expected4 = File.readlines("data/value.expected").to_s.chomp

    @cdata_xml = File.readlines("data/bug_cdata.xml").to_s.chomp
    @cdata_expected = File.readlines("data/bug_cdata.expected").to_s.chomp

    @fault_doc = File.readlines("data/fault.xml").to_s
  end

  # test parseMethodResponse --------------------------------------------------
  
  def test_parseMethodResponse1
    assert_equal(@expected1, @p.parseMethodResponse(@xml1).inspect)
  end

  def test_parseMethodResponse2
    assert_equal(@expected2, @p.parseMethodResponse(@xml2).inspect)
  end

  def test_parseMethodResponse3
    assert_equal(@expected3, @p.parseMethodResponse(@xml3).inspect)
  end

  def test_cdata
    assert_equal(@cdata_expected, @p.parseMethodResponse(@cdata_xml).inspect)
  end

  # test parseMethodCall ------------------------------------------------------

  def test_parseMethodCall
    assert_equal(@expected4, @p.parseMethodCall(@xml4).inspect)
  end

  # test fault ----------------------------------------------------------------

  def test_fault
    flag, fault = @p.parseMethodResponse(@fault_doc)
     assert_equal(flag, false)
     unless fault.is_a? XMLRPC::FaultException
       assert(false, "must be an instance of class XMLRPC::FaultException")
     end
     assert_equal(fault.faultCode, 4)
     assert_equal(fault.faultString, "an error message")
  end
end

# create test class for each installed parser 
XMLRPC::XMLParser.each_installed_parser do |parser|
  klass = parser.class
  name = klass.to_s.split("::").last

  eval %{
    class Test_#{name} < Test::Unit::TestCase
      include GenericParserTest

      def setup
        super
        @p = #{klass}.new
      end
    end
  }
end
