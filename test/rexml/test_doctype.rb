# frozen_string_literal: false

require_relative "rexml_test_utils"

module REXMLTests
  class TestDocTypeAccessor < Test::Unit::TestCase
    def setup
      @sysid = "urn:x-test:sysid1"
      @notation_id1 = "urn:x-test:notation1"
      @notation_id2 = "urn:x-test:notation2"
      xml_system = <<-XML
      <!DOCTYPE root SYSTEM "#{@sysid}" [
        <!NOTATION n1 SYSTEM "#{@notation_id1}">
        <!NOTATION n2 SYSTEM "#{@notation_id2}">
      ]>
      <root/>
      XML
      @doc_type_system = REXML::Document.new(xml_system).doctype

      @pubid = "TEST_ID"
      xml_public_system = <<-XML
      <!DOCTYPE root PUBLIC "#{@pubid}" "#{@sysid}">
      <root/>
      XML
      @doc_type_public_system = REXML::Document.new(xml_public_system).doctype
    end

    def test_public
      assert_equal([
                     nil,
                     @pubid,
                   ],
                   [
                     @doc_type_system.public,
                     @doc_type_public_system.public,
                   ])
    end

    def test_to_s
      assert_equal("<!DOCTYPE root PUBLIC \"#{@pubid}\" \"#{@sysid}\">",
                   @doc_type_public_system.to_s)
    end

    def test_to_s_apostrophe
      @doc_type_public_system.parent.context[:prologue_quote] = :apostrophe
      assert_equal("<!DOCTYPE root PUBLIC '#{@pubid}' '#{@sysid}'>",
                   @doc_type_public_system.to_s)
    end

    def test_system
      assert_equal([
                     @sysid,
                     @sysid,
                   ],
                   [
                     @doc_type_system.system,
                     @doc_type_public_system.system,
                   ])
    end

    def test_notation
      assert_equal([
                     @notation_id1,
                     @notation_id2,
                   ],
                   [
                     @doc_type_system.notation("n1").system,
                     @doc_type_system.notation("n2").system,
                   ])
    end

    def test_notations
      notations = @doc_type_system.notations
      assert_equal([
                     @notation_id1,
                     @notation_id2,
                   ],
                   notations.collect(&:system))
    end
  end

  class TestNotationDeclPublic < Test::Unit::TestCase
    def setup
      @name = "vrml"
      @id = "VRML 1.0"
      @uri = "http://www.web3d.org/"
    end

    def test_to_s
      assert_equal("<!NOTATION #{@name} PUBLIC \"#{@id}\">",
                   decl(@id, nil).to_s)
    end

    def test_to_s_with_uri
      assert_equal("<!NOTATION #{@name} PUBLIC \"#{@id}\" \"#{@uri}\">",
                   decl(@id, @uri).to_s)
    end

    def test_to_s_apostrophe
      document = REXML::Document.new(<<-XML)
      <!DOCTYPE root SYSTEM "urn:x-test:sysid" [
        #{decl(@id, @uri).to_s}
      ]>
      <root/>
      XML
      document.context[:prologue_quote] = :apostrophe
      notation = document.doctype.notations[0]
      assert_equal("<!NOTATION #{@name} PUBLIC '#{@id}' '#{@uri}'>",
                   notation.to_s)
    end

    private
    def decl(id, uri)
      REXML::NotationDecl.new(@name, "PUBLIC", id, uri)
    end
  end

  class TestNotationDeclSystem < Test::Unit::TestCase
    def setup
      @name = "gif"
      @id = "gif viewer"
    end

    def test_to_s
      assert_equal("<!NOTATION #{@name} SYSTEM \"#{@id}\">",
                   decl(@id).to_s)
    end

    def test_to_s_apostrophe
      document = REXML::Document.new(<<-XML)
      <!DOCTYPE root SYSTEM "urn:x-test:sysid" [
        #{decl(@id).to_s}
      ]>
      <root/>
      XML
      document.context[:prologue_quote] = :apostrophe
      notation = document.doctype.notations[0]
      assert_equal("<!NOTATION #{@name} SYSTEM '#{@id}'>",
                   notation.to_s)
    end

    private
    def decl(id)
      REXML::NotationDecl.new(@name, "SYSTEM", id, nil)
    end
  end
end
