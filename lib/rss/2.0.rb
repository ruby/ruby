require "rss/0.9"

module RSS

	class Rss

		class Channel

			%w(generator ttl).each do |x|
				install_text_element(x)
				install_model(x, '?')
			end

			%w(category).each do |x|
				install_have_child_element(x)
				install_model(x, '?')
			end

			[
				["image", "?"],
				["language", "?"],
			].each do |x, occurs|
				install_model(x, occurs)
			end

			def other_element(convert, indent)
				rv = <<-EOT
#{category_element(convert, indent)}
#{generator_element(convert, indent)}
#{ttl_element(convert, indent)}
EOT
				rv << super
			end
			
			private
			alias children09 children
			def children
				children09 + [@category].compact
			end

			alias _tags09 _tags
			def _tags
				%w(generator ttl category).delete_if do |x|
					send(x).nil?
				end.collect do |elem|
					[nil, elem]
				end + _tags09
			end

			Category = Item::Category

			class Item
			
				[
					["comments", "?"],
					["author", "?"],
				].each do |x, occurs|
					install_text_element(x)
					install_model(x, occurs)
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
			
				def other_element(convert, indent)
					rv = <<-EOT
#{author_element(false, indent)}
#{comments_element(false, indent)}
#{pubDate_element(false, indent)}
#{guid_element(false, indent)}
EOT
					rv << super
				end

				private
				alias children09 children
				def children
					children09 + [@guid].compact
				end

				alias _tags09 _tags
				def _tags
					%w(comments author pubDate guid).delete_if do |x|
						send(x).nil?
					end.collect do |elem|
						[nil, elem]
					end + _tags09
				end

				class Guid < Element
					
					include RSS09

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

					def to_s(convert=true, indent=calc_indent)
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

	RSS09::ELEMENTS.each do |x|
		BaseListener.install_get_text_element(x, nil, "#{x}=")
	end

end
