=begin
= Win32OLE extension module

== WIN32OLE 
=== Constants
: VERSION
    The version number of WIN32OLE.

: ARGV
    The argument of the method invoked recently.
    This constant is used to get value of argument 
    when the argument is passed by reference.

=== Class Method
: connect(oleserver)
   returns running OLE automation object or WIN32OLE object from moniker.

: const_load(ole [,obj])
   defines the constants of OLE automation
   server as 'obj' class constants. If 'obj' omitted, the default
   is WIN32OLE.

: new(oleserver)
   returns OLE Automation object.

: ole_free(obj)
   invokes Release method of Dispatch interface of WIN32OLE object.
   This method should not be used because this method exists for debugging WIN32OLE.

: ole_reference_count(obj)
   returns reference counter of Dispatch interface.
   This method should not be used because this method exists for debugging WIN32OLE.

: ole_show_help(info [,helpcontext])
   displays helpfile.
   The first argument specifies WIN32OLE_TYPE object or WIN32OLE_METHOD object 
   or helpfile.

=== Method
: self[property]
   gets property of OLE object.

: self[property]=
   sets property of OLE object.

: _invoke(dispid, args, types)
   runs the early binding method.
   The dispid specifies Dispatch ID, args specifies the array of arguments,
   types specifies array of the type of arguments.

: each {...}
   Iterates over each item of OLE collection which has IEnumVARIANT
   interface.

: invoke(method, args,...)
   runs OLE method.

: ole_func_methods
   returns array of WIN32OLE_METHOD object which corresponds with function.

: ole_get_methods
   returns array of WIN32OLE_METHOD object which corresponds with get properties.

: ole_method(method)
   returns WIN32OLE_METHOD object which coreesponds with method 
   which specified by argument.

: ole_method_help(method)
   alias of ole_method.

: ole_methods
   returns WIN32OLE_METHOD object which coreesponds with method.

: ole_obj_help
   returns WIN32OLE_TYPE object.

: ole_put_methods
   returns array of WIN32OLE_METHOD object which corresponds with put properties.

: setproperty(property, key, val)
   set property of OLE object. 
   This method is used when the property has argument.

   For example, in VB
     obj.item("key") = val
   in Win32OLE
     obj.setproperty("item", "key", val)


== WIN32OLE_EVENT class

=== Class Method

: new(ole, interface)
   The new class method creates OLE event sink object to connect ole.
   The ole must be WIN32OLE object, and interface is the interface
   name of event.

: message_loop
    The message_loop class method translates and dispatches Windows 
    message.

=== Method
: on_event([event]){...}
    defines the callback of event.
    If event omitted, defines the callback of all events.

: on_event_with_outargs([event]) {...}
    defines the callback of event.
    If you want modify argument in callback, 

== WIN32OLE_METHOD

=== Class Methods
: new(win32ole_type, method)    
   creates WIN32OLE_METHOD object.

=== Methods
: dispid
   returns Dispatch ID.

: event?
   returns true if the method is event.

: event_interface
   returns interface name of event if the method is event.

: helpcontext
   returns help context.

: helpfile
   returns help file.

: invkind
   returns invkind.

: invoke_kind
   returns invoke kind string.

: name
   returns name of method.

: offset_vtbl
   returns the offset of Vtbl.

: params
   returns array of WIN32OLE_PARAM object.

: return_type
   returns string of return value type of method.

: return_vtype
   returns number of return value type of method.

: return_type_detail
   returns detail information of return value type of method.

: size_params
   returns the size of arguments.

: size_opt_params
   returns the size of optional arguments.

: visible?
   returns true if the method is public.

== WIN32OLE_PARAM
: default
   returns default value.

: input?
   returns true if argument is input.

: optional?
   returns true if argument is optional.

: output?
   returns true if argument is output.

: name
   returns name.

: ole_type
   returns type of argument.

: ole_type_detail
   returns detail information of type of argument.

: retval?
   returns true if argument is return value.

== WIN32OLE_TYPE
=== Class Methods
: new(typelibrary, class)
    returns WIN32OLE_TYPE object.

: ole_classes(typelibrary)
    returns array of WIN32OLE_TYPE objects defined by Type Library.

: progids
    returns array of ProgID.

: typelibs
    returns array of type libraries.

=== Methods
: guid
   returns GUID.

: helpfile
   returns helpfile.

: helpcontext
   returns helpcontext.

: helpstring
   returns help string.

: major_version
   returns major version.

: minor_version
   returns minor version.

: name
   returns name.

: ole_methods
   returns array of WIN32OLE_METHOD objects.

: ole_type
   returns type of class.

: progid
   returns ProgID if it exists. If not found, then returns nil.

: src_type
   returns source class when the OLE class is 'Alias'.

: typekind
   returns number which represents type.

: variables
   returns array of variables defined in OLE class.

: visible?
   returns true if the OLE class is public.

== WIN32OLE_VARIABLE
=== Methods
: name
   returns the name.

: ole_type
   returns type

: ole_type_detail
   returns detail information of type.

: value
   returns value.

: variable_kind
   returns variable kind string.

: varkind
   returns the number which represents variable kind.

== WIN32OLE::VARIANT
=== Constants
  *VT_I4
  *VT_R4
  *VT_R8
  *VT_CY
  *VT_DATE
  *VT_BSTR
  *VT_USERDEFINED
  *VT_PTR
  *VT_DISPATCH
  *VT_ERROR
  *VT_BOOL
  *VT_VARIANT
  *VT_UNKNOWN
  *VT_I1
  *VT_UI1
  *VT_UI2
  *VT_UI4
  *VT_INT
  *VT_UINT
  *VT_ARRAY
  *VT_BYREF

=end

