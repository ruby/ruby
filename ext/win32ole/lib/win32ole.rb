begin
  require 'win32ole.so'
rescue LoadError
  # do nothing
end

if defined?(WIN32OLE)
  # WIN32OLE
  class WIN32OLE

    #
    # By overriding Object#methods, WIN32OLE might
    # work well with did_you_mean gem.
    # This is exprimental.
    #
    #  require 'win32ole'
    #  dict = WIN32OLE.new('Scripting.Dictionary')
    #  dict.Ade('a', 1)
    #  #=> Did you mean?  Add
    #
    def methods(*args)
      super + ole_methods.map(&:name)
    end
  end
end
