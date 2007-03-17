require "rexml/document"

require "rss-testcase"

require "rss/atom"

module RSS
  class TestAtomCore < TestCase
    def setup
      @uri = "http://www.w3.org/2005/Atom"
      @xhtml_uri = "http://www.w3.org/1999/xhtml"
    end

    def test_feed
      version = "1.0"
      encoding = "UTF-8"
      standalone = false

      feed = Atom::Feed.new(version, encoding, standalone)
      assert_equal("", feed.to_s)

      author = feed.class::Author.new
      name = feed.class::Author::Name.new
      name.content = "an author"
      author.name = name
      assert_not_equal("", author.to_s)
      feed.authors << author
      assert_equal("", feed.to_s)

      id = feed.class::Id.new
      id.content = "http://example.com/atom.xml"
      assert_not_equal("", id.to_s)
      feed.id = id
      assert_equal("", feed.to_s)

      title = feed.class::Title.new
      title.content = "a title"
      assert_not_equal("", title.to_s)
      feed.title = title
      assert_equal("", feed.to_s)

      updated = feed.class::Updated.new
      updated.content = Time.now
      assert_not_equal("", updated.to_s)
      feed.updated = updated
      assert_not_equal("", feed.to_s)


      feed.authors.clear
      assert_equal("", feed.to_s)
      entry = Atom::Feed::Entry.new
      setup_entry(entry)
      assert_not_equal("", entry.to_s)

      author = entry.authors.first
      entry.authors.clear
      assert_equal("", entry.to_s)
      entry.parent = feed
      assert_equal("", entry.to_s)
      feed.authors << author
      assert_not_equal("", entry.to_s)
      feed.authors.clear
      feed.entries << entry
      assert_equal("", feed.to_s)
      entry.authors << author
      assert_not_equal("", entry.to_s)
      assert_not_equal("", feed.to_s)

      doc = REXML::Document.new(feed.to_s)
      xmldecl = doc.xml_decl

      %w(version encoding).each do |x|
        assert_equal(instance_eval(x), xmldecl.__send__(x))
      end
      assert_equal(standalone, !xmldecl.standalone.nil?)

      assert_equal(@uri, doc.root.namespace)
    end

    def test_entry
      version = "1.0"
      encoding = "UTF-8"
      standalone = false

      entry = Atom::Entry.new(version, encoding, standalone)
      setup_entry(entry)

      author = entry.authors.first
      entry.authors.clear
      assert_equal("", entry.to_s)
      source = Atom::Entry::Source.new
      source.authors << author
      entry.source = source
      assert_not_equal("", entry.to_s)

      doc = REXML::Document.new(entry.to_s)
      xmldecl = doc.xml_decl

      %w(version encoding).each do |x|
        assert_equal(instance_eval(x), xmldecl.__send__(x))
      end
      assert_equal(standalone, !xmldecl.standalone.nil?)

      assert_equal(@uri, doc.root.namespace)
    end

    def test_not_displayed_xml_stylesheets
      feed = Atom::Feed.new
      plain_feed = feed.to_s
      3.times do
        feed.xml_stylesheets.push(XMLStyleSheet.new)
        assert_equal(plain_feed, feed.to_s)
      end
    end

    def test_atom_author
      assert_atom_person_to_s(Atom::Feed::Author)
      assert_atom_person_to_s(Atom::Feed::Entry::Author)
      assert_atom_person_to_s(Atom::Entry::Author)
      assert_atom_person_to_s(Atom::Feed::Entry::Source::Author)
      assert_atom_person_to_s(Atom::Entry::Source::Author)
    end

    def test_atom_category
      assert_atom_category_to_s(Atom::Feed::Category)
      assert_atom_category_to_s(Atom::Feed::Entry::Category)
      assert_atom_category_to_s(Atom::Entry::Category)
      assert_atom_category_to_s(Atom::Feed::Entry::Source::Category)
      assert_atom_category_to_s(Atom::Entry::Source::Category)
    end

    def test_atom_contributor
      assert_atom_person_to_s(Atom::Feed::Contributor)
      assert_atom_person_to_s(Atom::Feed::Entry::Contributor)
      assert_atom_person_to_s(Atom::Entry::Contributor)
      assert_atom_person_to_s(Atom::Feed::Entry::Source::Contributor)
      assert_atom_person_to_s(Atom::Entry::Source::Contributor)
    end

    def test_atom_generator
      assert_atom_generator_to_s(Atom::Feed::Generator)
      assert_atom_generator_to_s(Atom::Feed::Entry::Source::Generator)
      assert_atom_generator_to_s(Atom::Entry::Source::Generator)
    end

    def test_atom_icon
      assert_atom_icon_to_s(Atom::Feed::Icon)
      assert_atom_icon_to_s(Atom::Feed::Entry::Source::Icon)
      assert_atom_icon_to_s(Atom::Entry::Source::Icon)
    end

    def test_atom_id
      assert_atom_id_to_s(Atom::Feed::Id)
      assert_atom_id_to_s(Atom::Feed::Entry::Id)
      assert_atom_id_to_s(Atom::Entry::Id)
      assert_atom_id_to_s(Atom::Feed::Entry::Source::Id)
      assert_atom_id_to_s(Atom::Entry::Source::Id)
    end

    def test_atom_link
      assert_atom_link_to_s(Atom::Feed::Link)
      assert_atom_link_to_s(Atom::Feed::Entry::Link)
      assert_atom_link_to_s(Atom::Entry::Link)
      assert_atom_link_to_s(Atom::Feed::Entry::Source::Link)
      assert_atom_link_to_s(Atom::Entry::Source::Link)
    end

    def test_atom_logo
      assert_atom_logo_to_s(Atom::Feed::Logo)
      assert_atom_logo_to_s(Atom::Feed::Entry::Source::Logo)
      assert_atom_logo_to_s(Atom::Entry::Source::Logo)
    end

    def test_atom_rights
      assert_atom_text_construct_to_s(Atom::Feed::Rights)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Rights)
      assert_atom_text_construct_to_s(Atom::Entry::Rights)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Source::Rights)
      assert_atom_text_construct_to_s(Atom::Entry::Source::Rights)
    end

    def test_atom_subtitle
      assert_atom_text_construct_to_s(Atom::Feed::Subtitle)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Source::Subtitle)
      assert_atom_text_construct_to_s(Atom::Entry::Source::Subtitle)
    end

    def test_atom_title
      assert_atom_text_construct_to_s(Atom::Feed::Title)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Title)
      assert_atom_text_construct_to_s(Atom::Entry::Title)
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Source::Title)
      assert_atom_text_construct_to_s(Atom::Entry::Source::Title)
    end

    def test_atom_updated
      assert_atom_date_construct_to_s(Atom::Feed::Updated)
      assert_atom_date_construct_to_s(Atom::Feed::Entry::Updated)
      assert_atom_date_construct_to_s(Atom::Entry::Updated)
      assert_atom_date_construct_to_s(Atom::Feed::Entry::Source::Updated)
      assert_atom_date_construct_to_s(Atom::Entry::Source::Updated)
    end

    def test_atom_content
      assert_atom_content_to_s(Atom::Feed::Entry::Content)
      assert_atom_content_to_s(Atom::Entry::Content)
    end

    def test_atom_published
      assert_atom_date_construct_to_s(Atom::Feed::Entry::Published)
      assert_atom_date_construct_to_s(Atom::Entry::Published)
    end

    def test_atom_summary
      assert_atom_text_construct_to_s(Atom::Feed::Entry::Summary)
      assert_atom_text_construct_to_s(Atom::Entry::Summary)
    end


    def test_to_xml
      atom = RSS::Parser.parse(make_feed)
      assert_equal(atom.to_s, atom.to_xml)
      assert_equal(atom.to_s, atom.to_xml("atom"))
      assert_equal(atom.to_s, atom.to_xml("atom1.0"))
      assert_equal(atom.to_s, atom.to_xml("atom1.0:feed"))
      assert_equal(atom.to_s, atom.to_xml("atom:feed"))

      rss09_xml = atom.to_xml("0.91") do |maker|
        maker.channel.language = "en-us"
        maker.channel.link = "http://example.com/"
        maker.channel.description.content = atom.title.content

        maker.image.url = "http://example.com/logo.png"
        maker.image.title = "Logo"
      end
      rss09 = RSS::Parser.parse(rss09_xml)
      assert_equal(["rss", "0.91", nil], rss09.feed_info)

      rss20_xml = atom.to_xml("2.0") do |maker|
        maker.channel.link = "http://example.com/"
        maker.channel.description.content = atom.title.content
      end
      rss20 = RSS::Parser.parse(rss20_xml)
      assert_equal("2.0", rss20.rss_version)
      assert_equal(["rss", "2.0", nil], rss20.feed_info)
    end

    private
    def setup_entry(entry)
      _wrap_assertion do
        assert_equal("", entry.to_s)

        author = entry.class::Author.new
        name = entry.class::Author::Name.new
        name.content = "an author"
        author.name = name
        assert_not_equal("", author.to_s)
        entry.authors << author
        assert_equal("", entry.to_s)

        id = entry.class::Id.new
        id.content = "http://example.com/atom.xml"
        assert_not_equal("", id.to_s)
        entry.id = id
        assert_equal("", entry.to_s)

        title = entry.class::Title.new
        title.content = "a title"
        assert_not_equal("", title.to_s)
        entry.title = title
        assert_equal("", entry.to_s)

        updated = entry.class::Updated.new
        updated.content = Time.now
        assert_not_equal("", updated.to_s)
        entry.updated = updated
        assert_not_equal("", entry.to_s)
      end
    end
  end
end
