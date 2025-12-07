# frozen_string_literal: true

require 'objspace.so'

module ObjectSpace
  class << self
    private :_dump
    private :_dump_all
    private :_dump_shapes
  end

  module_function

  # Dump the contents of a ruby object as JSON.
  #
  # _output_ can be one of: +:stdout+, +:file+, +:string+, or IO object.
  #
  # * +:file+ means dumping to a tempfile and returning corresponding File object;
  # * +:stdout+ means printing the dump and returning +nil+;
  # * +:string+ means returning a string with the dump;
  # * if an instance of IO object is provided, the output goes there, and the object
  #   is returned.
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


  # Dump the contents of the ruby heap as JSON.
  #
  # _output_ argument is the same as for #dump.
  #
  # _full_ must be a boolean. If true, all heap slots are dumped including the empty ones (+T_NONE+).
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

  #  Dump the contents of the ruby shape tree as JSON.
  #
  #  _output_ argument is the same as for #dump.
  #
  #  If _since_ is a positive integer, only shapes newer than the provided
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

  # call-seq:
  #    ObjectSpace.find_paths_to_unshareable_objects(obj) {|path| ... } -> nil
  #    ObjectSpace.find_paths_to_unshareable_objects(obj) -> enumerator
  #
  # Finds all unshareable objects reachable from +obj+.
  #
  # When called with a block, yields an array representing the path from +obj+ to
  # each unshareable object found. The path includes all intermediate objects
  # traversed, ending with the unshareable object itself.
  #
  # If +obj+ itself is shareable, no paths are yielded.
  #
  # Example:
  #
  #   class Container
  #     attr_reader :value
  #     def initialize(value)
  #       @value = value
  #     end
  #   end
  #
  #   mutable_string = "hello"
  #   container = Container.new(mutable_string)
  #
  #   pp ObjectSpace.find_paths_to_unshareable_objects(container).to_a
  #     #=> [
  #       [#<Container:0x00007fc35843e388 @value="hello">],
  #       [#<Container:0x00007fc35843e388 @value="hello">, "hello"]
  #     ]
  def find_paths_to_unshareable_objects(obj)
    return to_enum(__method__, obj) if !block_given?

    queue = [[obj, []]]
    visited = Set.new

    while current = queue.shift
      current_obj, current_path = current
      visited.add(current_obj.object_id)

      if !Ractor.shareable?(current_obj)
        yield current_path + [current_obj]

        ObjectSpace.reachable_objects_from(current_obj).each do |reachable|
          if !reachable.is_a?(ObjectSpace::InternalObjectWrapper) && !visited.include?(reachable.object_id)
            queue.push([reachable, current_path + [current_obj]])
          end
        end
      end
    end
  end
end
