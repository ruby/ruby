# ATTENSION:
#  TrackBack handling API MUST be CHANGED!!!!

require 'rss/1.0'
require 'rss/2.0'

module RSS

  TRACKBACK_PREFIX = 'trackback'
  TRACKBACK_URI = 'http://madskills.com/public/xml/rss/module/trackback/'

  RDF.install_ns(TRACKBACK_PREFIX, TRACKBACK_URI)
  Rss.install_ns(TRACKBACK_PREFIX, TRACKBACK_URI)

	module BaseTrackBackModel
    def trackback_validate(tags)
			raise unless @do_validate
      counter = {}
      %w(ping about).each do |x|
				counter["#{TRACKBACK_PREFIX}_#{x}"] = 0
			end

      tags.each do |tag|
        key = "#{TRACKBACK_PREFIX}_#{tag}"
        raise UnknownTagError.new(tag, TRACKBACK_URI) unless counter.has_key?(key)
        counter[key] += 1
				if tag != "about" and counter[key] > 1
					raise TooMuchTagError.new(tag, tag_name)
				end
			end

			if counter["#{TRACKBACK_PREFIX}_ping"].zero? and
					counter["#{TRACKBACK_PREFIX}_about"].nonzero?
				raise MissingTagError.new("#{TRACKBACK_PREFIX}:ping", tag_name)
			end
		end
	end

  module TrackBackModel10
    extend BaseModel
		include BaseTrackBackModel

		def self.append_features(klass)
			super

			unless klass.class == Module
				%w(ping).each do |x|
					klass.install_have_child_element("#{TRACKBACK_PREFIX}_#{x}")
				end
				
				%w(about).each do |x|
					klass.install_have_children_element("#{TRACKBACK_PREFIX}_#{x}")
				end
			end
		end

		class Ping < Element
			include RSS10

			class << self

				def required_prefix
					TRACKBACK_PREFIX
				end
				
				def required_uri
					TRACKBACK_URI
				end

			end
			
			[
				["resource", ::RSS::RDF::URI, true]
			].each do |name, uri, required|
				install_get_attribute(name, uri, required)
			end

			def initialize(resource=nil)
				super()
				@resource = resource
			end

			def to_s(convert=true)
				if @resource
					rv = %Q!<#{TRACKBACK_PREFIX}:ping #{::RSS::RDF::PREFIX}:resource="#{h @resource}"/>!
					rv = @converter.convert(rv) if convert and @converter
					rv
				else
					''
				end
			end

			private
			def _attrs
				[
					["resource", true],
				]
			end

		end

		class About < Element
			include RSS10

			class << self
				
				def required_prefix
					TRACKBACK_PREFIX
				end
				
				def required_uri
					TRACKBACK_URI
				end

			end
			
			[
				["resource", ::RSS::RDF::URI, true]
			].each do |name, uri, required|
				install_get_attribute(name, uri, required)
			end

			def initialize(resource=nil)
				super()
				@resource = resource
			end

			def to_s(convert=true)
				if @resource
					rv = %Q!<#{TRACKBACK_PREFIX}:about #{::RSS::RDF::PREFIX}:resource="#{h @resource}"/>!
					rv = @converter.convert(rv) if convert and @converter
					rv
				else
					''
				end
			end

			private
			def _attrs
				[
					["resource", true],
				]
			end

		end
	end

	module TrackBackModel20
		include BaseTrackBackModel
		extend BaseModel

		def self.append_features(klass)
			super

			unless klass.class == Module
				%w(ping).each do |x|
					klass.install_have_child_element("#{TRACKBACK_PREFIX}_#{x}")
				end
				
				%w(about).each do |x|
					klass.install_have_children_element("#{TRACKBACK_PREFIX}_#{x}")
				end
			end
		end

		class Ping < Element
			include RSS09

			content_setup

			class << self

				def required_prefix
					TRACKBACK_PREFIX
				end
				
				def required_uri
					TRACKBACK_URI
				end

			end
			
			def to_s(convert=true)
				if @content
					rv = %Q!<#{TRACKBACK_PREFIX}:ping>#{h @content}</#{TRACKBACK_PREFIX}:ping>!
					rv = @converter.convert(rv) if convert and @converter
					rv
				else
					''
				end
			end

		end

		class About < Element
			include RSS09

			content_setup

			class << self
				
				def required_prefix
					TRACKBACK_PREFIX
				end
				
				def required_uri
					TRACKBACK_URI
				end

			end
			
			def to_s(convert=true)
				if @content
					rv = %Q!<#{TRACKBACK_PREFIX}:about>#{h @content}</#{TRACKBACK_PREFIX}:about>!
					rv = @converter.convert(rv) if convert and @converter
					rv
				else
					''
				end
			end

		end
	end

  class RDF
    class Item; include TrackBackModel10; end
  end

	class Rss
		class Channel
			class Item; include TrackBackModel20; end
		end
	end

end
