assert_normal_exit %q{
  eval("", TOPLEVEL_BINDING)
  minobj = ObjectSpace.to_enum(:each_object).min_by {|a| a.object_id }
  maxobj = ObjectSpace.to_enum(:each_object).max_by {|a| a.object_id }
  minobj.object_id.upto(maxobj.object_id) {|id|
    begin
      o = ObjectSpace._id2ref(id)
    rescue RangeError
      next
    end
    o.inspect if defined?(o.inspect)
  }
}, '[ruby-dev:31911]'
