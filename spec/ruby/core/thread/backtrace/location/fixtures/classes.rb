# These are top-level def on purpose to test those cases

def label_top_method = ThreadBacktraceLocationSpecs::LABEL.call

def self.label_sdef_method_of_main = ThreadBacktraceLocationSpecs::LABEL.call

class << self
  def label_sclass_method_of_main = ThreadBacktraceLocationSpecs::LABEL.call
end

module ThreadBacktraceLocationSpecs
  MODULE_LOCATION = caller_locations(0) rescue nil
  INSTANCE = Object.new.extend(self)
  LABEL = -> { caller_locations(1, 1)[0].label }

  def self.locations
    caller_locations
  end

  def instance_method_location
    caller_locations(0)
  end

  def self.method_location
    caller_locations(0)
  end

  def self.block_location
    1.times do
      return caller_locations(0)
    end
  end

  def instance_block_location
    1.times do
      return caller_locations(0)
    end
  end

  def self.locations_inside_nested_blocks
    first_level_location = nil
    second_level_location = nil
    third_level_location = nil

    1.times do
      first_level_location = locations[0]
      1.times do
        second_level_location = locations[0]
        1.times do
          third_level_location = locations[0]
        end
      end
    end

    [first_level_location, second_level_location, third_level_location]
  end

  def instance_locations_inside_nested_block
    loc = nil
    1.times do
      1.times do
        loc = caller_locations(0)
      end
    end
    loc
  end

  def original_method = LABEL.call
  alias_method :aliased_method, :original_method

  module M
    class C
      def regular_instance_method = LABEL.call

      def self.sdef_class_method = LABEL.call

      class << self
        def sclass_method = LABEL.call

        def block_in_sclass_method
          -> {
            -> { LABEL.call }.call
          }.call
        end
      end
      block_in_sclass_method
    end
  end

  class M::D
    def scoped_method = LABEL.call

    def self.sdef_scoped_method = LABEL.call

    class << self
      def sclass_scoped_method = LABEL.call
    end

    module ::ThreadBacktraceLocationSpecs
      def top = LABEL.call
    end

    class ::ThreadBacktraceLocationSpecs::Nested
      def top_nested = LABEL.call

      class C
        def top_nested_c = LABEL.call
      end
    end
  end

  SOME_OBJECT = Object.new
  SOME_OBJECT.instance_exec do
    def unknown_def_singleton_method = LABEL.call

    def self.unknown_sdef_singleton_method = LABEL.call
  end

  M.module_eval do
    def module_eval_method = LABEL.call

    def self.sdef_module_eval_method = LABEL.call
  end

  def ThreadBacktraceLocationSpecs.string_class_method = LABEL.call

  module M
    def ThreadBacktraceLocationSpecs.nested_class_method = LABEL.call
  end

  module M
    module_function def mod_function = LABEL.call
  end

  expr = self
  def expr.sdef_expression = LABEL.call

  def expr.block_in_sdef_expression = -> { LABEL.call }.call
end
