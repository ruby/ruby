require "rss/0.9"

module RSS

	class Rss

		URI = "http://backend.userland.com/rss2"

		install_ns('', URI)
		
		def self.required_uri
			URI
		end

		class Channel

			def self.required_uri
				URI
			end

			%w(generator ttl).each do |x|
				install_text_element(x)
			end

			%w(category).each do |x|
				install_have_child_element(x)
			end

			[
				["image", "?"],
			].each do |x, occurs|
				install_model(x, occurs)
			end

			def other_element(convert, indent='')
				rv = <<-EOT
#{indent}#{category_element(convert)}
#{indent}#{generator_element(convert)}
#{indent}#{ttl_element(convert)}
EOT
				rv << super
			end

			Category = Item::Category
			def Category.required_uri
				URI
			end

			class Item
			
				def self.required_uri
					URI
				end

				[
					["pubDate", '?'],
				].each do |x, occurs|
					install_date_element(x, 'rfc822')
					install_model(x, occurs)
				end

				[
					["guid", '?'],
				].each do |x, occurs|
					install_have_child_element(x)
					install_model(x, occurs)
				end
			
				def other_element(convert, indent='')
					rv = <<-EOT
#{indent}#{pubDate_element(false)}
#{indent}#{guid_element(false)}
EOT
					rv << super
				end

				class Guid < Element
					
					include RSS09

					def self.required_uri
						URI
					end

					[
						["isPermaLink", nil, false]
					].each do |name, uri, required|
						install_get_attribute(name, uri, required)
					end

					content_setup

					def initialize(isPermaLink=nil, content=nil)
						super()
						@isPermaLink = isPermaLink
						@content = content
					end

					def to_s(convert=true)
						if @content
							rv = %Q!<guid!
							rv << %Q! isPermaLink="#{h @isPermaLink}"! if @isPermaLink
							rv << %Q!>#{h @content}</guid>!
							rv = @converter.convert(rv) if convert and @converter
							rv
						else
							''
						end
					end

					private
					def _attrs
						[
							["isPermaLink", false]
						]
					end

				end

			end

		end

	end

	if const_defined?(:BaseListener)
		RSS09::ELEMENTS.each do |x|
			BaseListener.install_get_text_element(x, Rss::URI, "#{x}=")
		end
	end

	if const_defined?(:ListenerMixin)
		module ListenerMixin
			private
			def start_rss(tag_name, prefix, attrs, ns)
				check_ns(tag_name, prefix, ns, Rss::URI)

				@rss = Rss.new(attrs['version'], @version, @encoding, @standalone)
				@last_element = @rss
				@proc_stack.push Proc.new { |text, tags|
					@rss.validate_for_stream(tags) if @do_validate
				}
			end
					
		end
	end

end
