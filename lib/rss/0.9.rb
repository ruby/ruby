require "rss/rss"

module RSS

	module RSS09
		NSPOOL = {}
		ELEMENTS = []
	end

	class Rss < Element

		include RSS09

		[
			["channel", nil],
		].each do |tag, occurs|
			install_model(tag, occurs)
		end

		%w(channel).each do |x|
			install_have_child_element(x)
		end

		attr_accessor :rss_version, :version, :encoding, :standalone
		
		def initialize(rss_version, version=nil, encoding=nil, standalone=nil)
			super()
			@rss_version = rss_version
			@version = version || '1.0'
			@encoding = encoding
			@standalone = standalone
		end

		def output_encoding=(enc)
			@output_encoding = enc
			self.converter = Converter.new(@output_encoding, @encoding)
		end
		
		def items
			if @channel
				@channel.items
			else
				[]
			end
		end

		def image
			if @channel
				@channel.image
			else
				nil
			end
		end

		def to_s(convert=true)
			rv = <<-EOR
#{xmldecl}
<rss version="#{@rss_version}"#{ns_declaration}>
#{channel_element(false)}
#{other_element(false, "\t")}
</rss>
EOR
      rv = @converter.convert(rv) if convert and @converter
      rv
		end

		private
		def xmldecl
			rv = "<?xml version='#{@version}'"
			if @output_encoding or @encoding
				rv << " encoding='#{@output_encoding or @encoding}'" 
			end
			rv << " standalone='#{@standalone}'" if @standalone
			rv << '?>'
			rv
		end

		def ns_declaration
			rv = ''
			NSPOOL.each do |prefix, uri|
				prefix = ":#{prefix}" unless prefix.empty?
				rv << %Q|\n\txmlns#{prefix}="#{uri}"|
			end
			rv
		end
		
		def children
			[@channel]
		end

		class Channel < Element

			include RSS09

			[
				["title", nil],
			 ["link", nil],
			 ["description", nil],
			 ["language", nil],
			 ["copyright", "?"],
			 ["managingEditor", "?"],
			 ["webMaster", "?"],
			 ["rating", "?"],
			 ["docs", "?"],
			 ["skipDays", "?"],
			 ["skipHours", "?"],
			].each do |x, occurs|
				install_text_element(x)
				install_model(x, occurs)
			end

			[
				["pubDate", "?"],
			 ["lastBuildDate", "?"],
			].each do |x, occurs|
				install_date_element(x, 'rfc822')
				install_model(x, occurs)
			end

			[
				["image", nil],
			 ["textInput", "?"],
			 ["cloud", "?"]
			].each do |x, occurs|
				install_have_child_element(x)
				install_model(x, occurs)
			end
			
			[
				["item", "*"]
			].each do |x, occurs|
				install_have_children_element(x)
				install_model(x, occurs)
			end

			def initialize()
				super()
			end

			def to_s(convert=true)
				rv = <<-EOT
	<channel>
		#{title_element(false)}
		#{link_element(false)}
		#{description_element(false)}
		#{language_element(false)}
		#{copyright_element(false)}
		#{managingEditor_element(false)}
		#{webMaster_element(false)}
		#{rating_element(false)}
		#{pubDate_element(false)}
		#{lastBuildDate_element(false)}
		#{docs_element(false)}
		#{skipDays_element(false)}
		#{skipHours_element(false)}
		#{image_element(false)}
#{item_elements(false)}
		#{textInput_element(false)}
#{other_element(false, "\t\t")}
	</channel>
EOT
	      rv = @converter.convert(rv) if convert and @converter
  	    rv
			end

	    private
			def children
				[@image, @textInput, @cloud, *@item]
			end

			class Image < Element

				include RSS09
				
				%w(url title link width height description).each do |x|
					install_text_element(x)
				end

				def to_s(convert=true)
					rv = <<-EOT
			<image>
				#{url_element(false)}
				#{title_element(false)}
				#{link_element(false)}
				#{width_element(false)}
				#{height_element(false)}
				#{description_element(false)}
#{other_element(false, "\t\t\t\t")}
			</image>
EOT
	     		rv = @converter.convert(rv) if convert and @converter
	  	    rv
				end

			end
			
			class Cloud < Element

				include RSS09
				
				[
					["domain", nil, false],
					["port", nil, false],
					["path", nil, false],
					["registerProcedure", nil, false],
					["protocol", nil ,false],
				].each do |name, uri, required|
					install_get_attribute(name, uri, required)
				end

				def to_s(convert=true)
					rv = <<-EOT
			<cloud
				domain="#{h @domain}"
				port="#{h @port}"
				path="#{h @path}"
				registerProcedure="#{h @registerProcedure}"
				protocol="#{h @protocol}"/>
EOT
	     		rv = @converter.convert(rv) if convert and @converter
	  	    rv
				end

			end
			
			class Item < Element
				
				include RSS09

				%w(title link description author comments).each do |x|
					install_text_element(x)
				end

				%w(category source enclosure).each do |x|
					install_have_child_element(x)
				end

				[
					["title", '?'],
					["link", '?'],
					["description", '?'],
					["author", '?'],
					["comments", '?'],
					["category", '?'],
					["source", '?'],
					["enclosure", '?'],
				].each do |tag, occurs|
					install_model(tag, occurs)
				end

				def to_s(convert=true)
					rv = <<-EOT
			<item>
				#{title_element(false)}
				#{link_element(false)}
				#{description_element(false)}
				#{author_element(false)}
				#{category_element(false)}
				#{comments_element(false)}
				#{enclosure_element(false)}
				#{source_element(false)}
#{other_element(false, "\t\t\t\t")}
			</item>
EOT
	     		rv = @converter.convert(rv) if convert and @converter
	  	    rv
				end

				class Source < Element

					include RSS09

					[
						["url", nil, true]
					].each do |name, uri, required|
						install_get_attribute(name, uri, required)
					end

					content_setup

					def initialize(url=nil, content=nil)
						super()
						@url = url
						@content = content
					end

					def to_s(convert=true)
						if @url
							rv = %Q!				<source url="#{@url}">!
							rv << %Q!#{@content}</source>!
							rv = @converter.convert(rv) if convert and @converter
							rv
						else
							''
						end
					end

					private
					def _attrs
						[
							["url", true]
						]
					end

				end

				class Enclosure < Element

					include RSS09

					[
						["url", nil, true],
					 ["length", nil, true],
					 ["type", nil, true],
					].each do |name, uri, required|
						install_get_attribute(name, uri, required)
					end

					def initialize(url=nil, length=nil, type=nil)
						super()
						@url = url
						@length = length
						@type = type
					end

					def to_s(convert=true)
						if @url and @length and @type
							rv = %Q!<enclosure url="#{h @url}" !
							rv << %Q!length="#{h @length}" type="#{h @type}"/>!
							rv = @converter.convert(rv) if convert and @converter
							rv
						else
							''
						end
					end

					private
					def _attrs
						[
							["url", true],
						 ["length", true],
						 ["type", true],
						]
					end

				end

				class Category < Element

					include RSS09
					
					[
						["domain", nil, true]
					].each do |name, uri, required|
						install_get_attribute(name, uri, required)
					end

					content_setup

					def initialize(domain=nil, content=nil)
						super()
						@domain = domain
						@content = content
					end

					def to_s(convert=true)
						if @domain
							rv = %Q!<category domain="#{h @domain}">!
							rv << %Q!#{h @content}</category>!
							rv = @converter.convert(rv) if convert and @converter
							rv
						else
							''
						end
					end

					private
					def _attrs
						[
							["domain", true]
						]
					end

				end

			end
			
			class TextInput < Element
				
				include RSS09

				%w(title description name link).each do |x|
					install_text_element(x)
				end

				def to_s(convert=true)
					rv = <<-EOT
			<textInput>
				#{title_element(false)}
				#{description_element(false)}
				#{name_element(false)}
				#{link_element(false)}
#{other_element(false, "\t\t\t\t")}
			</textInput>
EOT
	     		rv = @converter.convert(rv) if convert and @converter
	  	    rv
				end

			end
			
		end
		
	end

	if const_defined?(:BaseListener)
		RSS09::ELEMENTS.each do |x|
			BaseListener.install_get_text_element(x, nil, "#{x}=")
		end
	end

	if const_defined?(:ListenerMixin)
		module ListenerMixin
			private
			def start_rss(tag_name, prefix, attrs, ns)
				check_ns(tag_name, prefix, ns, nil)

				@rss = Rss.new(attrs['version'], @version, @encoding, @standalone)
				@last_element = @rss
				@proc_stack.push Proc.new { |text, tags|
					@rss.validate_for_stream(tags) if @do_validate
				}
			end
					
		end
	end

end
