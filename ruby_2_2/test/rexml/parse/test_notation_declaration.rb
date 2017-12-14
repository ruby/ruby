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
    end

    class TestExternalID < self
      class TestSystem < self
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
  end
end
