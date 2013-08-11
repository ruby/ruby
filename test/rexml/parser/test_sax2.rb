require "test/unit"
require "rexml/parsers/sax2parser"
require "rexml/sax2listener"

class TestSAX2Parser < Test::Unit::TestCase
  class TestDocumentTypeDeclaration < self
    private
    def xml(internal_subset)
      <<-XML
<!DOCTYPE r SYSTEM "urn:x-henrikmartensson:test" [
#{internal_subset}
]>
<r/>
      XML
    end

    class TestEntityDecl < self
      class Listener
        include REXML::SAX2Listener
        attr_reader :entity_declarations
        def initialize
          @entity_declarations = []
        end

        def entitydecl(declaration)
          super
          @entity_declarations << declaration
        end
      end

      private
      def parse(internal_subset)
        listener = Listener.new
        parser = REXML::Parsers::SAX2Parser.new(xml(internal_subset))
        parser.listen(listener)
        parser.parse
        listener.entity_declarations
      end

      class TestGeneralEntity < self
        class TestValue < self
          def test_double_quote
            assert_equal([["name", "value"]], parse(<<-INTERNAL_SUBSET))
<!ENTITY name "value">
            INTERNAL_SUBSET
          end

          def test_single_quote
            assert_equal([["name", "value"]], parse(<<-INTERNAL_SUBSET))
<!ENTITY name 'value'>
            INTERNAL_SUBSET
          end
        end

        class TestExternlID < self
          class TestSystem < self
            def test_with_ndata
              declaration = [
                "name",
                "SYSTEM", "system-literal",
                "NDATA", "ndata-name",
              ]
              assert_equal([declaration],
                           parse(<<-INTERNAL_SUBSET))
<!ENTITY name SYSTEM "system-literal" NDATA ndata-name>
              INTERNAL_SUBSET
            end

            def test_without_ndata
              declaration = [
                "name",
                "SYSTEM", "system-literal",
              ]
              assert_equal([declaration],
                           parse(<<-INTERNAL_SUBSET))
<!ENTITY name SYSTEM "system-literal">
              INTERNAL_SUBSET
            end
          end

          class TestPublic < self
            def test_with_ndata
              declaration = [
                "name",
                "PUBLIC", "public-literal", "system-literal",
                "NDATA", "ndata-name",
              ]
              assert_equal([declaration],
                           parse(<<-INTERNAL_SUBSET))
<!ENTITY name PUBLIC "public-literal" "system-literal" NDATA ndata-name>
              INTERNAL_SUBSET
            end

            def test_without_ndata
              declaration = [
                "name",
                "PUBLIC", "public-literal", "system-literal",
              ]
              assert_equal([declaration], parse(<<-INTERNAL_SUBSET))
<!ENTITY name PUBLIC "public-literal" "system-literal">
              INTERNAL_SUBSET
            end
          end
        end
      end

      class TestParameterEntity < self
        class TestValue < self
          def test_double_quote
            assert_equal([["%", "name", "value"]], parse(<<-INTERNAL_SUBSET))
<!ENTITY % name "value">
            INTERNAL_SUBSET
          end

          def test_single_quote
            assert_equal([["%", "name", "value"]], parse(<<-INTERNAL_SUBSET))
<!ENTITY % name 'value'>
            INTERNAL_SUBSET
          end
        end

        class TestExternlID < self
          def test_system
            declaration = [
              "%",
              "name",
              "SYSTEM", "system-literal",
            ]
            assert_equal([declaration],
                           parse(<<-INTERNAL_SUBSET))
<!ENTITY % name SYSTEM "system-literal">
            INTERNAL_SUBSET
          end

          def test_public
            declaration = [
              "%",
              "name",
              "PUBLIC", "public-literal", "system-literal",
            ]
            assert_equal([declaration], parse(<<-INTERNAL_SUBSET))
<!ENTITY % name PUBLIC "public-literal" "system-literal">
            INTERNAL_SUBSET
          end
        end
      end
    end
  end
end
