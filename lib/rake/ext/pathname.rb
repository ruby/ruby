require 'rake/ext/core'
require 'pathname'

class Pathname

  rake_extension("ext") do
    # Return a new Pathname with <tt>String#ext</tt> applied to it.
    #
    # This Pathname extension comes from Rake
    def ext(newext='')
      Pathname.new(Rake.from_pathname(self).ext(newext))
    end
  end

  rake_extension("pathmap") do
    # Apply the pathmap spec to the Pathname, returning a
    # new Pathname with the modified paths.  (See String#pathmap for
    # details.)
    #
    # This Pathname extension comes from Rake
    def pathmap(spec=nil, &block)
      Pathname.new(Rake.from_pathname(self).pathmap(spec, &block))
    end
  end
end
