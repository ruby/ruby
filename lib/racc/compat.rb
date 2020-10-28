#--
#
#
#
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#
#++

unless Object.method_defined?(:__send)
  class Object
    alias __send __send__
  end
end

unless Object.method_defined?(:__send!)
  class Object
    alias __send! __send__
  end
end

unless Array.method_defined?(:map!)
  class Array
    if Array.method_defined?(:collect!)
      alias map! collect!
    else
      alias map! filter
    end
  end
end
