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
			
		end
	end
end

