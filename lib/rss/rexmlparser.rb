require "rexml/document"
require "rexml/streamlistener"

/\A(\d+)\.(\d+).\d+\z/ =~ REXML::Version
if $1.to_i < 2 or ($1.to_i == 2 and $2.to_i < 5)
	raise LoadError
end

module RSS
	
	class REXMLParser < BaseParser

		private

		def listener
			REXMLListener
		end

		def _parse
			begin
				REXML::Document.parse_stream(@rss, @listener)
			rescue RuntimeError => e
				raise NotWellFormedError.new{e.message}
			rescue REXML::ParseException => e
				context = e.context
				line = context[0] if context
				raise NotWellFormedError.new(line){e.message}
			end
		end
		
	end
	
	class REXMLListener < BaseListener

		include REXML::StreamListener
		include ListenerMixin

		def xmldecl(version, encoding, standalone)
			super
			# Encoding is converted to UTF-8 when REXML parse XML.
			@encoding = 'UTF-8'
		end

		alias_method(:cdata, :text)
	end

end
