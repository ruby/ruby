module Test
  module Unit
    module Assertions
      # For backward compatibility
      unless instance_methods.include?("assert_raise")
        def assert_raise(*args, &block)
          assert_raises(*args, &block)
        end
      end
    end
  end
end

module RSS
  module Assertions
    
    def assert_parse(rss, assert_method, *args)
      send("assert_#{assert_method}", *args) do
        ::RSS::Parser.parse(rss)
      end
      send("assert_#{assert_method}", *args) do
        ::RSS::Parser.parse(rss, false).validate
      end
    end
    
    def assert_ns(prefix, uri)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NSError")
        rescue ::RSS::NSError => e
          assert_equal(prefix, e.prefix)
          assert_equal(uri, e.uri)
        end
      end
    end
    
    def assert_missing_tag(tag, parent)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise MissingTagError")
        rescue ::RSS::MissingTagError => e
          assert_equal(tag, e.tag)
          assert_equal(parent, e.parent)
        end
      end
    end
    
    def assert_too_much_tag(tag, parent)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise TooMuchTagError")
        rescue ::RSS::TooMuchTagError => e
          assert_equal(tag, e.tag)
          assert_equal(parent, e.parent)
        end
      end
    end
    
    def assert_missing_attribute(tag, attrname)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise MissingAttributeError")
        rescue ::RSS::MissingAttributeError => e
          assert_equal(tag, e.tag)
          assert_equal(attrname, e.attribute)
        end
      end
    end
    
    def assert_not_excepted_tag(tag, parent)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NotExceptedTagError")
        rescue ::RSS::NotExceptedTagError => e
          assert_equal(tag, e.tag)
          assert_equal(parent, e.parent)
        end
      end
    end
    
    def assert_not_available_value(tag, value)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NotAvailableValueError")
        rescue ::RSS::NotAvailableValueError => e
          assert_equal(tag, e.tag)
          assert_equal(value, e.value)
        end
      end
    end

    def assert_not_set_error(name, variables)
      _wrap_assertion do
        begin
          yield
          flunk("Not raise NotSetError")
        rescue ::RSS::NotSetError => e
          assert_equal(name, e.name)
          assert_equal(variables.sort, e.variables.sort)
        end
      end
    end
    
    def assert_xml_declaration(version, encoding, standalone, rss)
      _wrap_assertion do
        assert_equal(version, rss.version)
        assert_equal(encoding, rss.encoding)
        assert_equal(standalone, rss.standalone)
      end
    end
    
    def assert_xml_stylesheet_attrs(attrs, xsl)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        ::RSS::XMLStyleSheet::ATTRIBUTES.each do |name|
          assert_equal(n_attrs[name], xsl.send(name))
        end
      end
    end
    
    def assert_xml_stylesheet(target, attrs, xsl)
      _wrap_assertion do
        if attrs.has_key?(:href)
          if !attrs.has_key?(:type) and attrs.has_key?(:guess_type)
            attrs[:type] = attrs[:guess_type]
          end
          assert_equal("xml-stylesheet", target)
          assert_xml_stylesheet_attrs(attrs, xsl)
        else
          assert_nil(target)
          assert_equal("", xsl.to_s)
        end
      end
    end
    
    def assert_xml_stylesheet_pis(attrs_ary)
      _wrap_assertion do
        rdf = ::RSS::RDF.new()
        xss_strs = []
        attrs_ary.each do |attrs|
          xss = ::RSS::XMLStyleSheet.new(*attrs)
          xss_strs.push(xss.to_s)
          rdf.xml_stylesheets.push(xss)
        end
        pi_str = rdf.to_s.gsub(/<\?xml .*\n/, "").gsub(/\s*<rdf:RDF.*\z/m, "")
        assert_equal(xss_strs.join("\n"), pi_str)
      end
    end

    def assert_xml_stylesheets(attrs, xss)
      _wrap_assertion do
        xss.each_with_index do |xs, i|
          assert_xml_stylesheet_attrs(attrs[i], xs)
        end
      end
    end

    
    def assert_channel10(attrs, channel)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        
        names = %w(about title link description)
        assert_attributes(attrs, names, channel)

        %w(image items textinput).each do |name|
          value = n_attrs[name]
          if value
            target = channel.__send__(name)
            __send__("assert_channel10_#{name}", value, target)
          end
        end
      end
    end

    def assert_channel10_image(attrs, image)
      _wrap_assertion do
        assert_attributes(attrs, %w(resource), image)
      end
    end
    
    def assert_channel10_textinput(attrs, textinput)
      _wrap_assertion do
        assert_attributes(attrs, %w(resource), textinput)
      end
    end

    def assert_channel10_items(attrs, items)
      _wrap_assertion do
        items.Seq.lis.each_with_index do |li, i|
          assert_attributes(attrs[i], %w(resource), li)
        end
      end
    end

    def assert_image10(attrs, image)
      _wrap_assertion do
        names = %w(about title url link)
        assert_attributes(attrs, names, image)
      end
    end

    def assert_items10(attrs, items)
      _wrap_assertion do
        names = %w(about title link description)
        items.each_with_index do |item, i|
          assert_attributes(attrs[i], names, item)
        end
      end
    end

    def assert_textinput10(attrs, textinput)
      _wrap_assertion do
        names = %w(about title description name link)
        assert_attributes(attrs, names, textinput)
      end
    end


    def assert_channel09(attrs, channel)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)

        names = %w(title description link language rating
                   copyright pubDate lastBuildDate docs
                   managingEditor webMaster)
        assert_attributes(attrs, names, channel)
        
        %w(skipHours skipDays).each do |name|
          value = n_attrs[name]
          if value
            target = channel.__send__(name)
            __send__("assert_channel09_#{name}", value, target)
          end
        end
      end
    end

    def assert_channel09_skipDays(contents, skipDays)
      _wrap_assertion do
        days = skipDays.days
        contents.each_with_index do |content, i|
          assert_equal(content, days[i].content)
        end
      end
    end
    
    def assert_channel09_skipHours(contents, skipHours)
      _wrap_assertion do
        hours = skipHours.hours
        contents.each_with_index do |content, i|
          assert_equal(content, hours[i].content)
        end
      end
    end
    
    def assert_image09(attrs, image)
      _wrap_assertion do
        names = %w(url link title description width height)
        assert_attributes(attrs, names, image)
      end
    end

    def assert_items09(attrs, items)
      _wrap_assertion do
        names = %w(title link description)
        items.each_with_index do |item, i|
          assert_attributes(attrs[i], names, item)
        end
      end
    end
    
    def assert_textinput09(attrs, textinput)
      _wrap_assertion do
        names = %w(title description name link)
        assert_attributes(attrs, names, textinput)
      end
    end


    def assert_channel20(attrs, channel)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        
        names = %w(title link description language copyright
                   managingEditor webMaster pubDate
                   lastBuildDate generator docs ttl rating)
        assert_attributes(attrs, names, channel)

        %w(cloud categories skipHours skipDays).each do |name|
          value = n_attrs[name]
          if value
            target = channel.__send__(name)
            __send__("assert_channel20_#{name}", value, target)
          end
        end
      end
    end

    def assert_channel20_skipDays(contents, skipDays)
      assert_channel09_skipDays(contents, skipDays)
    end
    
    def assert_channel20_skipHours(contents, skipHours)
      assert_channel09_skipHours(contents, skipHours)
    end
    
    def assert_channel20_cloud(attrs, cloud)
      _wrap_assertion do
        names = %w(domain port path registerProcedure protocol)
        assert_attributes(attrs, names, cloud)
      end
    end
    
    def assert_channel20_categories(attrs, categories)
      _wrap_assertion do
        names = %w(domain content)
        categories.each_with_index do |category, i|
          assert_attributes(attrs[i], names, category)
        end
      end
    end
    
    def assert_image20(attrs, image)
      _wrap_assertion do
        names = %w(url link title description width height)
        assert_attributes(attrs, names, image)
      end
    end

    def assert_items20(attrs, items)
      _wrap_assertion do
        names = %w(about title link description)
        items.each_with_index do |item, i|
          assert_attributes(attrs[i], names, item)

          n_attrs = normalized_attrs(attrs[i])

          %w(source enclosure categories guid).each do |name|
            value = n_attrs[name]
            if value
              target = item.__send__(name)
              __send__("assert_items20_#{name}", value, target)
            end
          end
        end
      end
    end

    def assert_items20_source(attrs, source)
      _wrap_assertion do
        assert_attributes(attrs, %w(url content), source)
      end
    end
    
    def assert_items20_enclosure(attrs, enclosure)
      _wrap_assertion do
        names = %w(url length type)
        assert_attributes(attrs, names, enclosure)
      end
    end
    
    def assert_items20_categories(attrs, categories)
      _wrap_assertion do
        assert_channel20_categories(attrs, categories)
      end
    end
    
    def assert_items20_guid(attrs, guid)
      _wrap_assertion do
        assert_attributes(attrs, %w(isPermaLink content), guid)
      end
    end

    def assert_textinput20(attrs, textinput)
      _wrap_assertion do
        names = %w(title description name link)
        assert_attributes(attrs, names, textinput)
      end
    end


    def assert_dublin_core(elems, target)
      _wrap_assertion do
        elems.each do |name, value|
          assert_equal(value, target.__send__("dc_#{name}"))
        end
      end
    end
    
    def assert_syndication(elems, target)
      _wrap_assertion do
        elems.each do |name, value|
          assert_equal(value, target.__send__("sy_#{name}"))
        end
      end
    end
    
    def assert_content(elems, target)
      _wrap_assertion do
        elems.each do |name, value|
          assert_equal(value, target.__send__("content_#{name}"))
        end
      end
    end
    
    def assert_trackback(attrs, target)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        if n_attrs["ping"]
          assert_equal(n_attrs["ping"], target.trackback_ping)
        end
        if n_attrs["abouts"]
          n_attrs["abouts"].each_with_index do |about, i|
            assert_equal(about, target.trackback_abouts[i].value)
          end
        end
      end
    end


    def assert_attributes(attrs, names, target)
      _wrap_assertion do
        n_attrs = normalized_attrs(attrs)
        names.each do |name|
          value = n_attrs[name]
          if value.is_a?(Time)
            actual = target.__send__(name)
            assert_instance_of(Time, actual)
            assert_equal(value.to_i, actual.to_i)
          elsif value
            assert_equal(value, target.__send__(name))
          end
        end
      end
    end
    
    def normalized_attrs(attrs)
      n_attrs = {}
      attrs.each do |name, value|
        n_attrs[name.to_s] = value
      end
      n_attrs
    end
    
  end
end
