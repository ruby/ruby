module REXML
	module Parsers
		class StreamParser
			def initialize source, listener
				@listener = listener
				@parser = BaseParser.new( source )
			end

			def parse
				# entity string
				while true
					event = @parser.pull
					case event[0]
					when :end_document
						return
					when :start_element
						@listener.tag_start( event[1], event[2] )
					when :end_element
						@listener.tag_end( event[1] )
					when :text
						normalized = @parser.unnormalize( event[1] )
						@listener.text( normalized )
					when :processing_instruction
						@listener.instruction( *event[1,2] )
					when :comment, :doctype, :attlistdecl, 
						:elementdecl, :entitydecl, :cdata, :notationdecl, :xmldecl
						@listener.send( event[0].to_s, *event[1..-1] )
					end
				end
			end
		end
	end
end
