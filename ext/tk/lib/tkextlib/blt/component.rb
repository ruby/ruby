#
#  tkextlib/blt/component.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/blt.rb'

module Tk::BLT
  module PlotComponent
    include TkItemConfigMethod

    module OptKeys
      def __item_font_optkeys(id)
        ['font', 'tickfont', 'titlefont']
      end
      private :__item_font_optkeys

      def __item_numstrval_optkeys(id)
        ['xoffset', 'yoffset']
      end
      private :__item_numstrval_optkeys

      def __item_boolval_optkeys(id)
        ['hide', 'under', 'descending', 'logscale', 'loose', 'showticks', 
          'titlealternate', 'scalesymbols', 'minor', 'raised', 
          'center', 'decoration', 'landscape', 'maxpect']
      end
      private :__item_boolval_optkeys

      def __item_strval_optkeys(id)
        ['text', 'label', 'limits', 'title', 
          'show', 'file', 'maskdata', 'maskfile']
      end
      private :__item_strval_optkeys

      def _item_listval_optkeys(id)
        ['bindtags']
      end
      private :__item_listval_optkeys

      def __item_numlistval_optkeys(id)
        ['dashes']
      end
      private :__item_numlistval_optkeys
    end
    include OptKeys

    def __item_cget_cmd(id)
      if id.kind_of?(Array)
        # id := [ type, name ]
        [self.path, id[0], 'cget', id[1]]
      else
        [self.path, id, 'cget']
      end
    end
    private :__item_cget_cmd

    def __item_config_cmd(id)
      if id.kind_of?(Array)
        # id := [ type, name ]
        [self.path, id[0], 'configure', id[1]]
      else
        [self.path, id, 'configure']
      end
    end
    private :__item_config_cmd

    def __item_pathname(id)
      if id.kind_of?(Array)
        id = tagid(id[1])
      end
      [self.path, id].join(';')
    end
    private :__item_pathname

    def axis_cget(id, option)
      ret = itemcget(['axis', id], option)
    end
    def axis_configure(id, slot, value=None)
      itemconfigure(['axis', id], slot, value)
    end
    def axis_configinfo(id, slot=nil)
      itemconfiginfo(['axis', id], slot)
    end
    def current_axis_configinfo(id, slot=nil)
      current_itemconfiginfo(['axis', id], slot)
    end

    def crosshairs_cget(option)
      itemcget('crosshairs', option)
    end
    def crosshairs_configure(slot, value=None)
      itemconfigure('crosshairs', slot, value)
    end
    def crosshairs_configinfo(slot=nil)
      itemconfiginfo('crosshairs', slot)
    end
    def current_crosshairs_configinfo(slot=nil)
      current_itemconfiginfo('crosshairs', slot)
    end

    def element_cget(id, option)
      itemcget(['element', id], option)
    end
    def element_configure(id, slot, value=None)
      itemconfigure(['element', id], slot, value)
    end
    def element_configinfo(id, slot=nil)
      itemconfiginfo(['element', id], slot)
    end
    def current_element_configinfo(id, slot=nil)
      current_itemconfiginfo(['element', id], slot)
    end

    def gridline_cget(option)
      itemcget('grid', option)
    end
    def gridline_configure(slot, value=None)
      itemconfigure('grid', slot, value)
    end
    def gridline_configinfo(slot=nil)
      itemconfiginfo('grid', slot)
    end
    def current_gridline_configinfo(slot=nil)
      current_itemconfiginfo('grid', slot)
    end

    def legend_cget(option)
      itemcget('legend', option)
    end
    def legend_configure(slot, value=None)
      itemconfigure('legend', slot, value)
    end
    def legend_configinfo(slot=nil)
      itemconfiginfo('legend', slot)
    end
    def current_legend_configinfo(slot=nil)
      current_itemconfiginfo('legend', slot)
    end

    def pen_cget(id, option)
      itemcget(['pen', id], option)
    end
    def pen_configure(id, slot, value=None)
      itemconfigure(['pen', id], slot, value)
    end
    def pen_configinfo(id, slot=nil)
      itemconfiginfo(['pen', id], slot)
    end
    def current_pen_configinfo(id, slot=nil)
      current_itemconfiginfo(['pen', id], slot)
    end

    def postscript_cget(option)
      itemcget('postscript', option)
    end
    def postscript_configure(slot, value=None)
      itemconfigure('postscript', slot, value)
    end
    def postscript_configinfo(slot=nil)
      itemconfiginfo('postscript', slot)
    end
    def current_postscript_configinfo(slot=nil)
      current_itemconfiginfo('postscript', slot)
    end

    def marker_cget(id, option)
      itemcget(['marker', id], option)
    end
    def marker_configure(id, slot, value=None)
      itemconfigure(['marker', id], slot, value)
    end
    def marker_configinfo(id, slot=nil)
      itemconfiginfo(['marker', id], slot)
    end
    def current_marker_configinfo(id, slot=nil)
      current_itemconfiginfo(['marker', id], slot)
    end

    alias __itemcget itemcget
    alias __itemconfiginfo itemconfiginfo
    alias __current_itemconfiginfo current_itemconfiginfo
    private :__itemcget, :__itemconfiginfo, :__current_itemconfiginfo

    def itemcget(tagOrId, option)
      ret = __itemcget(tagOrId, option)
      if option == 'bindtags' || option == :bindtags
        ret.collect{|tag| TkBindTag.id2obj(tag)}
      else
        ret
      end
    end
    def itemconfiginfo(tagOrId, slot = nil)
      ret = __itemconfiginfo(tagOrId, slot)

      if TkComm::GET_CONFIGINFO_AS_ARRAY
        if slot
          if slot == 'bindtags' || slot == :bindtags
            ret[-2] = ret[-2].collect{|tag| TkBindTag.id2obj(tag)}
            ret[-1] = ret[-1].collect{|tag| TkBindTag.id2obj(tag)}
          end
        else
          inf = ret.assoc('bindtags')
          inf[-2] = inf[-2].collect{|tag| TkBindTag.id2obj(tag)}
          inf[-1] = inf[-1].collect{|tag| TkBindTag.id2obj(tag)}
        end

      else # ! TkComm::GET_CONFIGINFO_AS_ARRAY
        if (inf = ret['bindtags'])
          inf[-2] = inf[-2].collect{|tag| TkBindTag.id2obj(tag)}
          inf[-1] = inf[-1].collect{|tag| TkBindTag.id2obj(tag)}
          ret['bindtags'] = inf
        end
      end

      ret
    end
    def current_itemconfiginfo(tagOrId, slot = nil)
      ret = __current_itemconfiginfo(tagOrId, slot)

      if (val = ret['bindtags'])
        ret['bindtags'] = val.collect{|tag| TkBindTag.id2obj(tag)}
      end

      ret
    end

    private :itemcget, :itemconfigure
    private :itemconfiginfo, :current_itemconfiginfo

    #################

    class Axis < TkObject
      OBJ_ID = ['blt_chart_axis'.freeze, '00000'.taint].freeze
      OBJ_TBL={}

      def self.id2obj(chart, id)
        cpath = chart.path
        return id unless OBJ_TBL[cpath]
        OBJ_TBL[cpath][id]? OBJ_TBL[cpath][id]: id
      end

      def self.new(chart, axis=nil, keys={})
        if axis.kind_of?(Hash)
          keys = axis
          axis = nil
        end
        OBJ_TBL[chart.path] = {} unless OBJ_TBL[chart.path]
        return OBJ_TBL[chart.path][axis] if axis && OBJ_TBL[chart.path][axis]
        super(chart, axis, keys)
      end

      def initialize(chart, axis=nil, keys={})
        if axis.kind_of?(Hash)
          keys = axis
          axis = nil
        end
        if axis
          @axis = @id = axis.to_s
        else
          @axis = @id = OBJ_ID.join(TkCore::INTERP._ip_id_).freeze
          OBJ_ID[1].succ!
        end
        @parent = @chart = chart
        @cpath = @chart.path
        Axis::OBJ_TBL[@cpath][@axis] = self
        keys = _symbolkey2str(keys)
        unless keys.delete['without_creating']
          @chart.axis_create(@axis, keys)
        end
      end

      def id
        @id
      end

      def to_eval
        @id
      end

      def cget(option)
        @chart.axis_cget(@id, option)
      end
      def configure(key, value=None)
        @chart.axis_configure(@id, key, value)
        self
      end
      def configinfo(key=nil)
        @chart.axis_configinfo(@id, key)
      end
      def current_configinfo(key=nil)
        @chart.current_axis_configinfo(@id, key)
      end

      def delete
        @chart.axis_delete(@id)
        self
      end

      def invtransform(val)
        @chart.axis_invtransform(@id, val)
      end

      def limits
        @chart.axis_limits(@id)
      end

      def name
        @axis
      end
        
      def transform(val)
        @chart.axis_transform(@id, val)
      end

      def view
        @chart.axis_view(@id)
        self
      end

      def use(name=None) # if @id == xaxis | x2axis | yaxis | y2axis
        @chart.axis_use(@id, name)
      end

      def use_as(axis) # axis := xaxis | x2axis | yaxis | y2axis
        @chart.axis_use(axis, @id)
      end
    end

    #################

    class Crosshairs < TkObject
      OBJ_TBL={}

      def self.new(chart, keys={})
        return OBJ_TBL[chart.path] if OBJ_TBL[chart.path]
        super(chart, keys)
      end

      def initialize(chart, keys={})
        @parent = @chart = chart
        @cpath = @chart.path
        Crosshairs::OBJ_TBL[@cpath] = self
        @chart.crosshair_configure(keys) unless keys.empty?
      end

      def id
        'crosshairs'
      end

      def to_eval
        'crosshairs'
      end

      def cget(option)
        @chart.crosshair_cget(option)
      end
      def configure(key, value=None)
        @chart.crosshair_configure(key, value)
        self
      end
      def configinfo(key=nil)
        @chart.crosshair_configinfo(key)
      end
      def current_configinfo(key=nil)
        @chart.current_crosshair_configinfo(key)
      end

      def off
        @chart.crosshair_off
        self
      end
      def on
        @chart.crosshair_on
        self
      end
      def toggle
        @chart.crosshair_toggle
        self
      end
    end

    #################

    class Element < TkObject
      OBJ_ID = ['blt_chart_element'.freeze, '00000'.taint].freeze
      OBJ_TBL={}

      def self.id2obj(chart, id)
        cpath = chart.path
        return id unless OBJ_TBL[cpath]
        OBJ_TBL[cpath][id]? OBJ_TBL[cpath][id]: id
      end

      def self.new(chart, element=nil, keys={})
        if element.kind_of?(Hash)
          keys = element
          element = nil
        end
        OBJ_TBL[chart.path] = {} unless OBJ_TBL[chart.path]
        if element && OBJ_TBL[chart.path][element]
          return OBJ_TBL[chart.path][element]
        end
        super(chart, element, keys)
      end

      def initialize(chart, element=nil, keys={})
        if element.kind_of?(Hash)
          keys = element
          element = nil
        end
        if element
          @element = @id = element.to_s
        else
          @element = @id = OBJ_ID.join(TkCore::INTERP._ip_id_).freeze
          OBJ_ID[1].succ!
        end
        @parent = @chart = chart
        @cpath = @chart.path
        Element::OBJ_TBL[@cpath][@element] = self
        keys = _symbolkey2str(keys)
        unless keys.delete['without_creating']
          @chart.element_create(@element, keys)
        end
      end

      def id
        @id
      end

      def to_eval
        @id
      end

      def cget(option)
        @chart.element_cget(@id, option)
      end
      def configure(key, value=None)
        @chart.element_configure(@id, key, value)
        self
      end
      def configinfo(key=nil)
        @chart.element_configinfo(@id, key)
      end
      def current_configinfo(key=nil)
        @chart.current_element_configinfo(@id, key)
      end

      def activate(*args)
        @chart.element_activate(@id, *args)
        self
      end

      def closest(x, y, var, keys={})
        @chart.element_closest(x, y, var, @id, keys)
      end

      def deactivate
        @chart.element_deactivate(@id)
        self
      end

      def delete
        @chart.element_delete(@id)
        self
      end

      def exist?
        @chart.element_exist?(@id)
      end

      def name
        @element
      end

      def type
        @chart.element_type(@id)
      end
    end

    #################

    class GridLine < TkObject
      OBJ_TBL={}

      def self.new(chart, keys={})
        return OBJ_TBL[chart.path] if OBJ_TBL[chart.path]
        super(chart, keys)
      end

      def initialize(chart, keys={})
        @parent = @chart = chart
        @cpath = @chart.path
        GridLine::OBJ_TBL[@cpath] = self
        @chart.gridline_configure(keys) unless keys.empty?
      end

      def id
        'grid'
      end

      def to_eval
        'grid'
      end

      def cget(option)
        @chart.gridline_cget(option)
      end
      def configure(key, value=None)
        @chart.gridline_configure(key, value)
        self
      end
      def configinfo(key=nil)
        @chart.gridline_configinfo(key)
      end
      def current_configinfo(key=nil)
        @chart.current_gridline_configinfo(key)
      end

      def off
        @chart.gridline_off
        self
      end
      def on
        @chart.gridline_on
        self
      end
      def toggle
        @chart.gridline_toggle
        self
      end
    end

    #################

    class Legend < TkObject
      OBJ_TBL={}

      def self.new(chart, keys={})
        return OBJ_TBL[chart.path] if OBJ_TBL[chart.path]
        super(chart, keys)
      end

      def initialize(chart, keys={})
        @parent = @chart = chart
        @cpath = @chart.path
        Crosshairs::OBJ_TBL[@cpath] = self
        @chart.crosshair_configure(keys) unless keys.empty?
      end

      def id
        'legend'
      end

      def to_eval
        'legend'
      end

      def cget(option)
        @chart.legend_cget(option)
      end
      def configure(key, value=None)
        @chart.legend_configure(key, value)
        self
      end
      def configinfo(key=nil)
        @chart.legend_configinfo(key)
      end
      def current_configinfo(key=nil)
        @chart.current_legend_configinfo(key)
      end

      def activate(*args)
        @chart.legend_activate(*args)
        self
      end

      def deactivate(*args)
        @chart.legend_deactivate(*args)
        self
      end

      def get(pos, y=nil)
        @chart.legend_get(pos, y)
      end
    end

    #################

    class Pen < TkObject
      OBJ_ID = ['blt_chart_pen'.freeze, '00000'.taint].freeze
      OBJ_TBL={}

      def self.id2obj(chart, id)
        cpath = chart.path
        return id unless OBJ_TBL[cpath]
        OBJ_TBL[cpath][id]? OBJ_TBL[cpath][id]: id
      end

      def self.new(chart, pen=nil, keys={})
        if pen.kind_of?(Hash)
          keys = pen
          pen = nil
        end
        OBJ_TBL[chart.path] = {} unless OBJ_TBL[chart.path]
        return OBJ_TBL[chart.path][pen] if pen && OBJ_TBL[chart.path][pen]
        super(chart, pen, keys)
      end

      def initialize(chart, pen=nil, keys={})
        if pen.kind_of?(Hash)
          keys = pen
          pen = nil
        end
        if pen
          @pen = @id = pen.to_s
        else
          @pen = @id = OBJ_ID.join(TkCore::INTERP._ip_id_).freeze
          OBJ_ID[1].succ!
        end
        @parent = @chart = chart
        @cpath = @chart.path
        Pen::OBJ_TBL[@cpath][@pen] = self
        keys = _symbolkey2str(keys)
        unless keys.delete['without_creating']
          @chart.pen_create(@pen, keys)
        end
      end

      def id
        @id
      end

      def to_eval
        @id
      end

      def cget(option)
        @chart.pen_cget(@id, option)
      end
      def configure(key, value=None)
        @chart.pen_configure(@id, key, value)
        self
      end
      def configinfo(key=nil)
        @chart.pen_configinfo(@id, key)
      end
      def current_configinfo(key=nil)
        @chart.current_pen_configinfo(@id, key)
      end

      def delete
        @chart.pen_delete(@id)
        self
      end

      def name
        @pen
      end
    end

    #################

    class Postscript < TkObject
      OBJ_TBL={}

      def self.new(chart, keys={})
        return OBJ_TBL[chart.path] if OBJ_TBL[chart.path]
        super(chart, keys)
      end

      def initialize(chart, keys={})
        @parent = @chart = chart
        @cpath = @chart.path
        Postscript::OBJ_TBL[@cpath] = self
        @chart.postscript_configure(keys) unless keys.empty?
      end

      def id
        'postscript'
      end

      def to_eval
        'postscript'
      end

      def cget(option)
        @chart.postscript_cget(option)
      end
      def configure(key, value=None)
        @chart.postscript_configure(key, value)
        self
      end
      def configinfo(key=nil)
        @chart.postscript_configinfo(key)
      end
      def current_configinfo(key=nil)
        @chart.current_postscript_configinfo(key)
      end

      def output(file=nil, keys={})
        if file.kind_of?(Hash)
          keys = file
          file = nil
        end

        ret = @chart.postscript_output(file, keys)

        if file
          self
        else
          ret
        end
      end
    end

    #################
    class Marker < TkObject
      extend Tk
      extend TkItemFontOptkeys
      extend TkItemConfigOptkeys

      extend Tk::BLT::PlotComponent::OptKeys

      MarkerTypeName = nil
      MarkerTypeToClass = {}
      MarkerID_TBL = TkCore::INTERP.create_table

      TkCore::INTERP.init_ip_env{ MarkerID_TBL.clear }

      def Marker.type2class(type)
        MarkerTypeToClass[type]
      end

      def Marker.id2obj(chart, id)
        cpath = chart.path
        return id unless MarkerID_TBL[cpath]
        MarkerID_TBL[cpath][id]? MarkerID_TBL[cpath][id]: id
      end

      def self._parse_create_args(keys)
        fontkeys = {}
        methodkeys = {}
        if keys.kind_of? Hash
          keys = _symbolkey2str(keys)

          __item_font_optkeys(nil).each{|key|
            fkey = key.to_s
            fontkeys[fkey] = keys.delete(fkey) if keys.key?(fkey)

            fkey = "kanji#{key}"
            fontkeys[fkey] = keys.delete(fkey) if keys.key?(fkey)

            fkey = "latin#{key}"
            fontkeys[fkey] = keys.delete(fkey) if keys.key?(fkey)

            fkey = "ascii#{key}"
            fontkeys[fkey] = keys.delete(fkey) if keys.key?(fkey)
          }

          __item_methodcall_optkeys(nil).each{|key|
            key = key.to_s
            methodkeys[key] = keys.delete(key) if keys.key?(key)
          }

          args = itemconfig_hash_kv(nil, keys)
        else
          args = []
        end

        [args, fontkeys]
      end
      private_class_method :_parse_create_args

      def self.create(chart, keys={})
        unless self::MarkerTypeName
          fail RuntimeError, "#{self} is an abstract class"
        end
        args, fontkeys = _parse_create_args(keys)
        idnum = tk_call_without_enc(chart.path, 'create', 
                                    self::MarkerTypeName, *args)
        chart.marker_configure(idnum, fontkeys) unless fontkeys.empty?
        idnum.to_i  # 'item id' is an integer number
      end

      def initialize(parent, *args)
        @parent = @chart = parent
        @path = parent.path

        @id = create_self(*args) # an integer number as 'item id'
        unless Tk::BLT::PlotComponent::MarkerID_TBL[@path]
          Tk::BLT::PlotComponent::MarkerID_TBL[@path] = {}
        end
        Tk::BLT::PlotComponent::MarkerID_TBL[@path][@id] = self
      end
      def create_self(*args)
        self.class.create(@chart, *args) # return an integer as 'item id'
      end
      private :create_self

      def id
        @id
      end

      def to_eval
        @id
      end

      def cget(option)
        @chart.marker_cget(@id, option)
      end
      def configure(key, value=None)
        @chart.marker_configure(@id, key, value)
        self
      end
      def configinfo(key=nil)
        @chart.marker_configinfo(@id, key)
      end
      def current_configinfo(key=nil)
        @chart.current_marker_configinfo(@id, key)
      end

      def after(target=None)
        @chart.marker_after(@id, target)
      end

      def before(target=None)
        @chart.marker_before(@id, target)
      end

      def delete
        @chart.marker_delete(@id)
      end

      def exist?
        @chart.marker_exist(@id)
      end

      def type
        @chart.marker_type(@id)
      end
    end

    class TextMarker < Marker
      MarkerTypeName = 'text'.freeze
      MarkerTypeToClass[MarkerTypeName] = self
    end
    class LineMarker < Marker
      MarkerTypeName = 'line'.freeze
      MarkerTypeToClass[MarkerTypeName] = self
    end
    class BitmapMarker < Marker
      MarkerTypeName = 'bitmap'.freeze
      MarkerTypeToClass[MarkerTypeName] = self
    end
    class ImageMarker < Marker
      MarkerTypeName = 'image'.freeze
      MarkerTypeToClass[MarkerTypeName] = self
    end
    class PolygonMarker < Marker
      MarkerTypeName = 'polygon'.freeze
      MarkerTypeToClass[MarkerTypeName] = self
    end
    class WindowMarker < Marker
      MarkerTypeName = 'window'.freeze
      MarkerTypeToClass[MarkerTypeName] = self
    end

    #################

    def __destroy_hook__
      Axis::OBJ_TBL.delete(@path)
      Crosshairs::OBJ_TBL.delete(@path)
      Element::OBJ_TBL.delete(@path)
      GridLine::OBJ_TBL.delete(@path)
      Legend::OBJ_TBL.delete(@path)
      Pen::OBJ_TBL.delete(@path)
      Postscript::OBJ_TBL.delete(@path)
      Marker::OBJ_TBL.delete(@path)
      super()
    end

    #################

    def tagid(tag)
      if tag.kind_of?(Axis) ||
          tag.kind_of?(Crosshairs) ||
          tag.kind_of?(Element) ||
          tag.kind_of?(GridLine) ||
          tag.kind_of?(Legend) ||
          tag.kind_of?(Pen) ||
          tag.kind_of?(Postscript) ||
          tag.kind_of?(Marker)
        tag.id
      else
        tag  # maybe an Array of configure paramters
      end
    end

    def _component_bind(target, tag, context, *args)
      if TkComm._callback_entry?(args[0])
        cmd = args.shift
      else
        cmd = Proc.new
      end
      _bind([path, target, 'bind', tagid(tag)], context, cmd, *args)
      self
    end
    def _component_bind_append(target, tag, context, *args)
      if TkComm._callback_entry?(args[0])
        cmd = args.shift
      else
        cmd = Proc.new
      end
      _bind_append([path, target, 'bind', tagid(tag)], context, cmd, *args)
      self
    end
    def _component_bind_remove(target, tag, context)
      _bind_remove([path, target, 'bind', tagid(tag)], context)
      self
    end
    def _component_bindinfo(target, tag, context=nil)
      _bindinfo([path, target, 'bind', tagid(tag)], context)
    end
    private :_component_bind, :_component_bind_append
    private :_component_bind_remove, :_component_bindinfo

    def axis_bind(tag, context, *args)
      _component_bind('axis', tag, context, *args)
    end
    def axis_bind_append(tag, context, *args)
      _component_bind_append('axis', tag, context, *args)
    end
    def axis_bind_remove(tag, context)
      _component_bind_remove('axis', tag, context)
    end
    def axis_bindinfo(tag, context=nil)
      _component_bindinfo('axis', tag, context)
    end

    def element_bind(tag, context, *args)
      _component_bind('element', tag, context, *args)
    end
    def element_bind_append(tag, context, *args)
      _component_bind_append('element', tag, context, *args)
    end
    def element_bind_remove(tag, context)
      _component_bind_remove('element', tag, context)
    end
    def element_bindinfo(tag, context=nil)
      _component_bindinfo('element', tag, context)
    end

    def legend_bind(tag, context, *args)
      _component_bind('legend', tag, context, *args)
    end
    def legend_bind_append(tag, context, *args)
      _component_bind_append('legend', tag, context, *args)
    end
    def legend_bind_remove(tag, context)
      _component_bind_remove('legend', tag, context)
    end
    def legend_bindinfo(tag, context=nil)
      _component_bindinfo('legend', tag, context)
    end

    def marker_bind(tag, context, *args)
      _component_bind('marker', tag, context, *args)
    end
    def marker_bind_append(tag, context, *args)
      _component_bind_append('marker', tag, context, *args)
    end
    def marker_bind_remove(tag, context)
      _component_bind_remove('marker', tag, context)
    end
    def marker_bindinfo(tag, context=nil)
      _component_bindinfo('marker', tag, context)
    end

    ###################

    def marker_create(type, *args)
      type.create(self, *args)
    end

    ###################

    def axis_delete(*ids)
      tk_send('axis', 'delete', *(ids.collect{|id| tagid(id)}))
      self
    end
    def axis_invtransform(id, val)
      list(tk_send('axis', 'invtransform', tagid(id), val))
    end
    def axis_limits(id)
      list(tk_send('axis', 'limits', tagid(id)))
    end
    def axis_names(*pats)
      simplelist(tk_send('axis', 'names', *pats)).collect{|axis|
        Axis.id2obj(self, axis)
      }
    end
    def axis_transform(id, val)
      list(tk_send('axis', 'transform', tagid(id), val))
    end
    def axis_view(id)
      tk_send('axis', 'view', tagid(id))
      self
    end
    def axis_use(id, target=nil)
      if target
        Axis.id2obj(self, tk_send('axis', 'use', tagid(id), tagid(target)))
      else
        Axis.id2obj(self, tk_send('axis', 'use', tagid(id)))
      end
    end

    ###################

    def crosshairs_off
      tk_send_without_enc('crosshairs', 'off')
      self
    end
    def crosshairs_on
      tk_send_without_enc('crosshairs', 'on')
      self
    end
    def crosshairs_toggle
      tk_send_without_enc('crosshairs', 'toggle')
      self
    end

    ###################

    def element_activate(id, *indices)
      tk_send('element', 'activate', tagid(id), *indices)
      self
    end
    def element_closest(x, y, var, *args)
      if args[-1].kind_of?(Hash)
        keys = args.pop
        bool(tk_send('element', 'activate', x, y, var, 
                     *(hash_kv(keys).concat(args))))
      else
        bool(tk_send('element', 'activate', x, y, var, *args))
      end
    end
    def element_deactivate(*ids)
      tk_send('element', 'deactivate', *(ids.collect{|id| tagid(id)}))
      self
    end
    def element_delete(*ids)
      tk_send('element', 'delete', *(ids.collect{|id| tagid(id)}))
      self
    end
    def element_exist?(id)
      bool(tk_send('element', 'exists', tagid(id)))
    end
    def element_names(*pats)
      simplelist(tk_send('element', 'names', *pats)).collect{|elem|
        Element.id2obj(self, elem)
      }
    end
    def element_show(*names)
      if names.empty?
        simplelist(tk_send('element', 'show'))
      else
        tk_send('element', 'show', *names)
        self
      end
    end
    def element_type(id)
      tk_send('element', 'type', tagid(id))
    end

    ###################

    def gridline_off
      tk_send_without_enc('grid', 'off')
      self
    end
    def gridline_on
      tk_send_without_enc('grid', 'on')
      self
    end
    def gridline_toggle
      tk_send_without_enc('grid', 'toggle')
      self
    end

    ###################

    def legend_activate(*pats)
      tk_send('legend', 'activate', *pats)
      self
    end
    def legend_deactivate(*pats)
      tk_send('legend', 'deactivate', *pats)
      self
    end
    def legend_get(pos, y=nil)
      if y
        Element.id2obj(self, tk_send('legend', 'get', _at(pos, y)))
      else
        Element.id2obj(self, tk_send('legend', 'get', pos))
      end
    end

    ###################

    def pen_delete(*ids)
      tk_send('pen', 'delete', *(ids.collect{|id| tagid(id)}))
      self
    end
    def pen_names(*pats)
      simplelist(tk_send('pen', 'names', *pats)).collect{|pen|
        Pen.id2obj(self, pen)
      }
    end

    ###################

    def postscript_output(file=nil, keys={})
      if file.kind_of?(Hash)
        keys = file
        file = nil
      end

      if file
        tk_send('postscript', 'output', file, keys)
        self
      else
        tk_send('postscript', 'output', keys)
      end
    end

    ###################

    def marker_after(id, target=nil)
      if target
        tk_send_without_enc('marker', 'after', tagid(id), tagid(target))
      else
        tk_send_without_enc('marker', 'after', tagid(id))
      end
      self
    end
    def marker_before(id, target=None)
      if target
        tk_send_without_enc('marker', 'before', tagid(id), tagid(target))
      else
        tk_send_without_enc('marker', 'before', tagid(id))
      end
      self
    end
    def marker_delete(*ids)
      tk_send('marker', 'delete', *(ids.collect{|id| tagid(id)}))
      self
    end
    def marker_exist?(id)
      bool(tk_send('marker', 'exists', tagid(id)))
    end
    def marker_names(*pats)
      simplelist(tk_send('marker', 'names', *pats)).collect{|id|
        Marker.id2obj(self, id)
      }
    end
    def marker_type(id)
      tk_send('marker', 'type', tagid(id))
    end

    ###################

    alias line_cget element_cget
    alias line_configure element_configure
    alias line_configinfo element_configinfo
    alias current_line_configinfo current_element_configinfo
    alias line_bind element_bind
    alias line_bind_append element_bind_append
    alias line_bind_remove element_bind_remove
    alias line_bindinfo element_bindinfo

    ###################

    def xaxis_cget(option)
      axis_cget('xaxis', option)
    end
    def xaxis_configure(slot, value=None)
      axis_configure('xaxis', slot, value)
    end
    def xaxis_configinfo(slot=nil)
      axis_configinfo('xaxis', slot)
    end
    def current_xaxis_configinfo(slot=nil)
      current_axis_configinfo('xaxis', slot)
    end
    def xaxis_invtransform(val)
      axis_invtransform('xaxis', val)
    end
    def xaxis_limits
      axis_limits('xaxis')
    end
    def xaxis_transform(val)
      axis_transform('xaxis', val)
    end
    def xaxis_use(target=nil)
      axis_use('xaxis', target)
    end

    def x2axis_cget(option)
      axis_cget('x2axis', option)
    end
    def x2axis_configure(slot, value=None)
      axis_configure('x2axis', slot, value)
    end
    def x2axis_configinfo(slot=nil)
      axis_configinfo('x2axis', slot)
    end
    def current_x2axis_configinfo(slot=nil)
      current_axis_configinfo('x2axis', slot)
    end
    def x2axis_invtransform(val)
      axis_invtransform('x2axis', val)
    end
    def x2axis_limits
      axis_limits('x2axis')
    end
    def x2axis_transform(val)
      axis_transform('x2axis', val)
    end
    def x2axis_use(target=nil)
      axis_use('x2axis', target)
    end

    def yaxis_cget(option)
      axis_cget('yaxis', option)
    end
    def yaxis_configure(slot, value=None)
      axis_configure('yaxis', slot, value)
    end
    def yaxis_configinfo(slot=nil)
      axis_configinfo('yaxis', slot)
    end
    def current_yaxis_configinfo(slot=nil)
      current_axis_configinfo('yaxis', slot)
    end
    def yaxis_invtransform(val)
      axis_invtransform('yaxis', val)
    end
    def yaxis_limits
      axis_limits('yaxis')
    end
    def yaxis_transform(val)
      axis_transform('yaxis', val)
    end
    def yaxis_use(target=nil)
      axis_use('yaxis', target)
    end

    def y2axis_cget(option)
      axis_cget('y2axis', option)
    end
    def y2axis_configure(slot, value=None)
      axis_configure('y2axis', slot, value)
    end
    def y2axis_configinfo(slot=nil)
      axis_configinfo('y2axis', slot)
    end
    def current_y2axis_configinfo(slot=nil)
      current_axis_configinfo('y2axis', slot)
    end
    def y2axis_invtransform(val)
      axis_invtransform('y2axis', val)
    end
    def y2axis_limits
      axis_limits('y2axis')
    end
    def y2axis_transform(val)
      axis_transform('y2axis', val)
    end
    def y2axis_use(target=nil)
      axis_use('y2axis', target)
    end
  end
end
