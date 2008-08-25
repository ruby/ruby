#!/usr/bin/env ruby

require 'rake'

module Rake

  # Base class for Task Libraries.
  class TaskLib

    include Cloneable

    # Make a symbol by pasting two strings together. 
    def paste(a,b)
      (a.to_s + b.to_s).intern
    end
  end

end
