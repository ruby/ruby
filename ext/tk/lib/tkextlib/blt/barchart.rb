#
#  tkextlib/blt/barchart.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/blt.rb'
require 'tkextlib/blt/component.rb'

module Tk::BLT
  class Barchart < TkWindow
    TkCommandNames = ['::blt::barchart'.freeze].freeze
    WidgetClassName = 'Barchart'.freeze
    WidgetClassNames[WidgetClassName] = self

    include PlotComponent

    def __boolval_optkeys
      ['bufferelements', 'invertxy']
    end
    private :__boolval_optkeys

    def __strval_optkeys
      ['text', 'label', 'title', 'file']
    end
    private :__strval_optkeys

    BarElement_ID = ['blt_barchart_bar'.freeze, '00000'.taint].freeze

    def bar(elem=nil, keys={})
      if elem.kind_of?(Hash)
        keys = elem
        elem = nil
      end
      unless elem
        elem = BarElement_ID.join(TkCore::INTERP._ip_id_).freeze
        BarElement_ID[1].succ!
      end
      tk_send('bar', elem, keys)
      Element.new(self, elem, :without_creating=>true)
    end

    def extents(item)
      num_or_str(tk_send_without_enc('extents', item))
    end

    def invtransform(x, y)
      list(tk_send_without_enc('invtransform', x, y))
    end

    def inside(x, y)
      bool(tk_send_without_enc('inside', x, y))
    end

    def metafile(file=None)
      # Windows only
      tk_send('metafile', file)
      self
    end

    def snap(output, keys={})
      tk_send_without_enc('snap', *(hash_kv(keys, false) + output))
      self
    end

    def transform(x, y)
      list(tk_send_without_enc('transform', x, y))
    end
  end
end
