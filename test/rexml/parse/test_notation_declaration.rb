# frozen_string_literal: false
require 'test/unit'
require 'rexml/document'

module REXMLTests
  class TestParseNotationDeclaration < Test::Unit::TestCase
    private
    def xml(internal_subset)
      <<-XML
<!DOCTYPE r SYSTEM "urn:x-henrikmartensson:test" [
#{internal_subset}
]>
<r/>
      XML
    end

    def parse(internal_subset)
      REXML::Document.new(xml(internal_subset)).doctype
    end

    class TestCommon < self
      def test_name
        doctype = parse("<!NOTATION name PUBLIC 'urn:public-id'>")
        assert_equal("name", doctype.notation("name").name)
      end

      def test_no_name
        exception = assert_raise(REXML::ParseException) do
          parse(<<-INTERNAL_SUBSET)
<!NOTATION>
          INTERNAL_SUBSET
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: name is missing
Line: 5
Position: 72
Last 80 unconsumed characters:
 <!NOTATION>  ]> <r/> 
        DETAIL
      end

      def test_invalid_name
        exception = assert_raise(REXML::ParseException) do
          parse(<<-INTERNAL_SUBSET)
<!NOTATION '>
          INTERNAL_SUBSET
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: invalid name
Line: 5
Position: 74
Last 80 unconsumed characters:
'>  ]> <r/> 
        DETAIL
      end

      def test_no_id_type
        exception = assert_raise(REXML::ParseException) do
          parse(<<-INTERNAL_SUBSET)
<!NOTATION name>
          INTERNAL_SUBSET
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: invalid ID type
Line: 5
Position: 77
Last 80 unconsumed characters:
>  ]> <r/> 
        DETAIL
      end

      def test_invalid_id_type
        exception = assert_raise(REXML::ParseException) do
          parse(<<-INTERNAL_SUBSET)
<!NOTATION name INVALID>
          INTERNAL_SUBSET
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: invalid ID type
Line: 5
Position: 85
Last 80 unconsumed characters:
 INVALID>  ]> <r/> 
        DETAIL
      end
    end

    class TestExternalID < self
      class TestSystem < self
        def test_no_literal
          exception = assert_raise(REXML::ParseException) do
            parse(<<-INTERNAL_SUBSET)
<!NOTATION name SYSTEM>
            INTERNAL_SUBSET
          end
          assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: system literal is missing
Line: 5
Position: 84
Last 80 unconsumed characters:
 SYSTEM>  ]> <r/> 
          DETAIL
        end

        def test_garbage_after_literal
          exception = assert_raise(REXML::ParseException) do
            parse(<<-INTERNAL_SUBSET)
<!NOTATION name SYSTEM 'system-literal'x'>
            INTERNAL_SUBSET
          end
          assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: garbage before end >
Line: 5
Position: 103
Last 80 unconsumed characters:
x'>  ]> <r/> 
          DETAIL
        end

        def test_single_quote
          doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name SYSTEM 'system-literal'>
          INTERNAL_SUBSET
          assert_equal("system-literal", doctype.notation("name").system)
        end

        def test_double_quote
          doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name SYSTEM "system-literal">
          INTERNAL_SUBSET
          assert_equal("system-literal", doctype.notation("name").system)
        end
      end

      class TestPublic < self
        class TestPublicIDLiteral < self
          def test_content_double_quote
            exception = assert_raise(REXML::ParseException) do
              parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC 'double quote " is invalid' "system-literal">
              INTERNAL_SUBSET
            end
            assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: invalid public ID literal
Line: 5
Position: 129
Last 80 unconsumed characters:
 PUBLIC 'double quote " is invalid' "system-literal">  ]> <r/> 
            DETAIL
          end

          def test_single_quote
            doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC 'public-id-literal' "system-literal">
            INTERNAL_SUBSET
            assert_equal("public-id-literal", doctype.notation("name").public)
          end

          def test_double_quote
            doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC "public-id-literal" "system-literal">
            INTERNAL_SUBSET
            assert_equal("public-id-literal", doctype.notation("name").public)
          end
        end

        class TestSystemLiteral < self
          def test_garbage_after_literal
            exception = assert_raise(REXML::ParseException) do
              parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC 'public-id-literal' 'system-literal'x'>
              INTERNAL_SUBSET
            end
            assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: garbage before end >
Line: 5
Position: 123
Last 80 unconsumed characters:
x'>  ]> <r/> 
           DETAIL
          end

          def test_single_quote
            doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC "public-id-literal" 'system-literal'>
            INTERNAL_SUBSET
            assert_equal("system-literal", doctype.notation("name").system)
          end

          def test_double_quote
            doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC "public-id-literal" "system-literal">
            INTERNAL_SUBSET
            assert_equal("system-literal", doctype.notation("name").system)
          end
        end
      end

      class TestMixed < self
        def test_system_public
          doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION system-name SYSTEM "system-literal">
<!NOTATION public-name PUBLIC "public-id-literal" 'system-literal'>
          INTERNAL_SUBSET
          assert_equal(["system-name", "public-name"],
                       doctype.notations.collect(&:name))
        end

        def test_public_system
          doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION public-name PUBLIC "public-id-literal" 'system-literal'>
<!NOTATION system-name SYSTEM "system-literal">
          INTERNAL_SUBSET
          assert_equal(["public-name", "system-name"],
                       doctype.notations.collect(&:name))
        end
      end
    end

    class TestPublicID < self
      def test_no_literal
        exception = assert_raise(REXML::ParseException) do
          parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC>
          INTERNAL_SUBSET
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: public ID literal is missing
Line: 5
Position: 84
Last 80 unconsumed characters:
 PUBLIC>  ]> <r/> 
        DETAIL
      end

      def test_literal_content_double_quote
        exception = assert_raise(REXML::ParseException) do
          parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC 'double quote " is invalid in PubidLiteral'>
          INTERNAL_SUBSET
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: invalid public ID literal
Line: 5
Position: 128
Last 80 unconsumed characters:
 PUBLIC 'double quote \" is invalid in PubidLiteral'>  ]> <r/> 
        DETAIL
      end

      def test_garbage_after_literal
        exception = assert_raise(REXML::ParseException) do
          parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC 'public-id-literal'x'>
          INTERNAL_SUBSET
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Malformed notation declaration: garbage before end >
Line: 5
Position: 106
Last 80 unconsumed characters:
x'>  ]> <r/> 
        DETAIL
      end

      def test_literal_single_quote
        doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC 'public-id-literal'>
        INTERNAL_SUBSET
        assert_equal("public-id-literal", doctype.notation("name").public)
      end

      def test_literal_double_quote
        doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION name PUBLIC "public-id-literal">
        INTERNAL_SUBSET
        assert_equal("public-id-literal", doctype.notation("name").public)
      end
    end
  end
end
