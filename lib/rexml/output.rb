require 'rexml/encoding'

module REXML
	class Output
		include Encoding
		attr_reader :encoding
		def initialize real_IO, encd="iso-8859-1"
			@output = real_IO
			self.encoding = encd

			eval <<-EOL
				alias :encode :to_#{encoding.tr('-', '_').downcase}
				alias :decode :from_#{encoding.tr('-', '_').downcase}
			EOL
			@to_utf = encd == UTF_8 ? false : true
		end

		def <<( content )
			@output << (@to_utf ? encode(content) : content)
		end
	end
end
