# -*- tab-width: 2 -*- vim: ts=2

module Test
	module Unit
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

			def assert_xml_stylesheet_attrs(xsl, attrs)
				_wrap_assertion do
					normalized_attrs = {}
					attrs.each do |name, value|
						normalized_attrs[name.to_s] = value
					end
					::RSS::XMLStyleSheet::ATTRIBUTES.each do |name|
						assert_equal(normalized_attrs[name], xsl.send(name))
					end
				end
			end
			
			def assert_xml_stylesheet(target, xsl, attrs)
				_wrap_assertion do
					if attrs.has_key?(:href)
						if !attrs.has_key?(:type) and attrs.has_key?(:guess_type)
							attrs[:type] = attrs[:guess_type]
						end
						assert_equal("xml-stylesheet", target)
						assert_xml_stylesheet_attrs(xsl, attrs)
					else
						assert_nil(target)
						assert_equal("", xsl.to_s)
					end
				end
			end
			
			def assert_xml_stylesheet_pis(attrs_ary)
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
	end
end

