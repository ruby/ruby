require 'rexml/encoding'
require 'rexml/source'

module REXML
	# NEEDS DOCUMENTATION
	class XMLDecl < Child
		include Encoding

		DEFAULT_VERSION = "1.0";
		DEFAULT_ENCODING = "UTF-8";
		DEFAULT_STANDALONE = "no";
		START = '<\?xml';
		STOP = '\?>';

		attr_accessor :version, :standalone

		def initialize(version=DEFAULT_VERSION, encoding=nil, standalone=nil)
			@encoding_set = !encoding.nil?
			if version.kind_of? XMLDecl
				super()
				@version = version.version
				self.encoding = version.encoding
				@standalone = version.standalone
			else
				super()
				@version = version
				self.encoding = encoding
				@standalone = standalone
			end
			@version = DEFAULT_VERSION if @version.nil?
		end

		def clone
			XMLDecl.new(self)
		end

		def write writer, indent=-1, transitive=false, ie_hack=false
			indent( writer, indent )
			writer << START.sub(/\\/u, '')
			writer << " #{content}"
			writer << STOP.sub(/\\/u, '')
		end

		def ==( other )
		  other.kind_of?(XMLDecl) and
		  other.version == @version and
		  other.encoding == self.encoding and
		  other.standalone == @standalone
		end

		def xmldecl version, encoding, standalone
			@version = version
			@encoding_set = !encoding.nil?
			self.encoding = encoding
			@standalone = standalone
		end

		def node_type
			:xmldecl
		end

		alias :stand_alone? :standalone

		private
		def content
			rv = "version='#@version'"
			rv << " encoding='#{encoding}'" if @encoding_set
			rv << " standalone='#@standalone'" if @standalone
			rv
		end
	end
end
