require "rexml/parseexception"

module REXML
	# Represents a node in the tree.  Nodes are never encountered except as
	# superclasses of other objects.  Nodes have siblings.
	module Node
		# @return the next sibling (nil if unset)
		def next_sibling_node
			return nil if @parent.nil?
			@parent[ @parent.index(self) + 1 ]
		end

		# @return the previous sibling (nil if unset)
		def previous_sibling_node
			return nil if @parent.nil?
			ind = @parent.index(self)
			return nil if ind == 0
			@parent[ ind - 1 ]
		end

		def to_s indent=-1
			rv = ""
			write rv,indent
			rv
		end

		def indent to, ind
 			if @parent and @parent.context and not @parent.context[:indentstyle].nil? then
 				indentstyle = @parent.context[:indentstyle]
 			else
 				indentstyle = '  '
 			end
 			to << indentstyle*ind unless ind<1
		end

		def parent?
			false;
		end
	end
end
