# frozen_string_literal: false
#
#  tkextlib/blt/graph.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/blt.rb'
require 'tkextlib/blt/component.rb'

module Tk::BLT
  class Graph < TkWindow
    TkCommandNames = ['::blt::graph'.freeze].freeze
    WidgetClassName = 'Graph'.freeze
    WidgetClassNames[WidgetClassName] ||= self

    include PlotComponent
    include GraphCommand

    def __boolval_optkeys
      ['bufferelements', 'invertxy']
    end
    private :__boolval_optkeys

    def __strval_optkeys
      ['text', 'label', 'title', 'file', 'plotbackground']
    end
    private :__strval_optkeys

=begin
    BarElement_ID = ['blt_graph_bar'.freeze, TkUtil.untrust('00000')].freeze

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
=end

    def extents(item)
      num_or_str(tk_send_without_enc('extents', item))
    end

    def invtransform(x, y)
      list(tk_send_without_enc('invtransform', x, y))
    end

    def inside(x, y)
      bool(tk_send_without_enc('inside', x, y))
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
