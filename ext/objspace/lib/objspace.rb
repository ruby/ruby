# frozen_string_literal: true

require 'objspace.so'

module ObjectSpace
  class << self
    private :_dump
    private :_dump_all
    private :_dump_shapes
  end

  module_function

  # call-seq:
  #   ObjectSpace.dump(obj[, output: :string]) -> "{ ... }"
  #   ObjectSpace.dump(obj, output: :file) -> #<File:/tmp/rubyobj20131125-88733-1xkfmpv.json>
  #   ObjectSpace.dump(obj, output: :stdout) -> nil
  #
  # Dump the contents of a ruby object as JSON.
  #
  # This method is only expected to work with C Ruby.
  # This is an experimental method and is subject to change.
  # In particular, the function signature and output format are
  # not guaranteed to be compatible in future versions of ruby.
  def dump(obj, output: :string)
    out = case output
    when :file, nil
      require 'tempfile'
      Tempfile.create(%w(rubyobj .json))
    when :stdout
      STDOUT
    when :string
      +''
    when IO
      output
    else
      raise ArgumentError, "wrong output option: #{output.inspect}"
    end

    ret = _dump(obj, out)
    return nil if output == :stdout
    ret
  end


  # call-seq:
  #   ObjectSpace.dump_all([output: :file]) -> #<File:/tmp/rubyheap20131125-88469-laoj3v.json>
  #   ObjectSpace.dump_all(output: :stdout) -> nil
  #   ObjectSpace.dump_all(output: :string) -> "{...}\n{...}\n..."
  #   ObjectSpace.dump_all(output: File.open('heap.json','w')) -> #<File:heap.json>
  #   ObjectSpace.dump_all(output: :string, since: 42) -> "{...}\n{...}\n..."
  #
  # Dump the contents of the ruby heap as JSON.
  #
  # _full_ must be a boolean. If true all heap slots are dumped including the empty ones (T_NONE).
  #
  # _since_ must be a non-negative integer or +nil+.
  #
  # If _since_ is a positive integer, only objects of that generation and
  # newer generations are dumped. The current generation can be accessed using
  # GC::count. Objects that were allocated without object allocation tracing enabled
  # are ignored. See ::trace_object_allocations for more information and
  # examples.
  #
  # If _since_ is omitted or is +nil+, all objects are dumped.
  #
  # _shapes_ must be a boolean or a non-negative integer.
  #
  # If _shapes_ is a positive integer, only shapes newer than the provided
  # shape id are dumped. The current shape_id can be accessed using <tt>RubyVM.stat(:next_shape_id)</tt>.
  #
  # If _shapes_ is +false+, no shapes are dumped.
  #
  # To only dump objects allocated past a certain point you can combine _since_ and _shapes_:
  #   ObjectSpace.trace_object_allocations
  #   GC.start
  #   gc_generation = GC.count
  #   shape_generation = RubyVM.stat(:next_shape_id)
  #   call_method_to_instrument
  #   ObjectSpace.dump_all(since: gc_generation, shapes: shape_generation)
  #
  # This method is only expected to work with C Ruby.
  # This is an experimental method and is subject to change.
  # In particular, the function signature and output format are
  # not guaranteed to be compatible in future versions of ruby.
  def dump_all(output: :file, full: false, since: nil, shapes: true)
    out = case output
    when :file, nil
      require 'tempfile'
      Tempfile.create(%w(rubyheap .json))
    when :stdout
      STDOUT
    when :string
      +''
    when IO
      output
    else
      raise ArgumentError, "wrong output option: #{output.inspect}"
    end

    shapes = 0 if shapes == true
    ret = _dump_all(out, full, since, shapes)
    return nil if output == :stdout
    ret
  end

  #  call-seq:
  #    ObjectSpace.dump_shapes([output: :file]) -> #<File:/tmp/rubyshapes20131125-88469-laoj3v.json>
  #    ObjectSpace.dump_shapes(output: :stdout) -> nil
  #    ObjectSpace.dump_shapes(output: :string) -> "{...}\n{...}\n..."
  #    ObjectSpace.dump_shapes(output: File.open('shapes.json','w')) -> #<File:shapes.json>
  #    ObjectSpace.dump_all(output: :string, since: 42) -> "{...}\n{...}\n..."
  #
  #  Dump the contents of the ruby shape tree as JSON.
  #
  #  If _shapes_ is a positive integer, only shapes newer than the provided
  #  shape id are dumped. The current shape_id can be accessed using <tt>RubyVM.stat(:next_shape_id)</tt>.
  #
  #  This method is only expected to work with C Ruby.
  #  This is an experimental method and is subject to change.
  #  In particular, the function signature and output format are
  #  not guaranteed to be compatible in future versions of ruby.
  def dump_shapes(output: :file, since: 0)
    out = case output
    when :file, nil
      require 'tempfile'
      Tempfile.create(%w(rubyshapes .json))
    when :stdout
      STDOUT
    when :string
      +''
    when IO
      output
    else
      raise ArgumentError, "wrong output option: #{output.inspect}"
    end

    ret = _dump_shapes(out, since)
    return nil if output == :stdout
    ret
  end
end
