#
#  tkextlib/ICONS/icons.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require File.join(File.dirname(File.expand_path(__FILE__)), 'setup.rb')

# TkPackage.require('icons', '1.0')
TkPackage.require('icons')

module Tk
  class ICONS < TkImage
    def self.create(*args)  # icon, icon, ..., keys
      if args[-1].kind_of?(Hash)
	keys = args.pop
	icons = simplelist(tk_call('::icons::icons', 'create', 
				   *(hash_kv(keys).concat(args.flatten))))
      else
	icons = simplelist(tk_call('::icons::icons', 'create', 
				   *(args.flatten)))
      end

      icons.collect{|icon| self.new(icon, :without_creating=>true)}
    end

    def self.delete(*icons)
      return if icons.empty?
      tk_call('::icons::icons', 'delete', icons)
    end

    def self.query(*args)
      if args[-1].kind_of?(Hash)
	keys = args.pop
	list(tk_call('::icons::icons', 'query', 
		     *(hash_kv(keys).concat(args.flatten))))
      else
	list(tk_call('::icons::icons', 'query', *(args.flatten)))
      end
    end

    ##########################################

    def self.new(name, keys=nil)
      Tk_IMGTBL["::icon::#{name}"] || super
    end

    def initialize(name, keys=nil)
      if name.kind_of?(String) && name =~ /^::icon::(.+)$/
	  @name = $1
	  @path = name
      else
	@name = name.to_s
	@path = "::icon::#{@name}"
      end
      keys = _symbolkey2str(keys)
      unless keys.delete('without_creating')
	tk_call('::icons::icons', 'create', *(hash_kv(keys) << @name))
      end
      Tk_IMGTBL[@path] = self
    end

    def name
      @name
    end

    def delete
      Tk_IMGTBL.delete(@path)
      tk_call('::icons::icons', 'delete', @name)
      self
    end

    def query(keys)
      list(simplelist(tk_call('::icons::icons', 'query', 
			       *(hash_kv(keys) << @name))
		      )[0])
    end
  end
end
