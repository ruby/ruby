$LOAD_PATH.unshift '../../lib'
require 'test/unit'
require 'xmlrpc/datetime'
require "xmlrpc/parser"

module GenericParserTest
  def setup
    @xml1 = File.read("data/xml1.xml")
    @expected1 = File.read("data/xml1.expected").chomp

    @xml2 = File.read("data/bug_covert.xml")
    @expected2 = File.read("data/bug_covert.expected").chomp

    @xml3 = File.read("data/bug_bool.xml")
    @expected3 = File.read("data/bug_bool.expected").chomp

    @xml4 = File.read("data/value.xml")
    @expected4 = File.read("data/value.expected").chomp

    @cdata_xml = File.read("data/bug_cdata.xml").chomp
    @cdata_expected = File.read("data/bug_cdata.expected").chomp

    @datetime_xml = File.read("data/datetime_iso8601.xml")
    @datetime_expected = XMLRPC::DateTime.new(2004, 11, 5, 1, 15, 23)

    @fault_doc = File.read("data/fault.xml").to_s
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

  def test_dateTime
    assert_equal(@datetime_expected, @p.parseMethodResponse(@datetime_xml)[1])
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
