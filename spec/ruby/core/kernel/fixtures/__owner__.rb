module KernelSpecs
  module OwnerTestModule
    def m0
      __owner__
    end

    alias m0_alias m0
    alias_method :m0_alias_method, :m0

    def m1
      __owner__
    end

    def in_block
      [0].map { __owner__ }
    end

    define_method(:dm) do
      __owner__
    end

    define_method(:dm_block) do
      [0].map { __owner__ }
    end

    def from_send
      send "__owner__"
    end

    def from_eval
      eval "__owner__"
    end
  end

  class OwnerTest
    include OwnerTestModule

    def m0
      super
    end

    alias m1_alias m1
    alias_method :m1_alias_method, :m1

    def in_block
      super
    end

    define_method(:dm) do
      super()
    end

    define_method(:dm_block) do
      super()
    end

    def from_send
      super
    end

    def from_eval
      super
    end

    @@method = __owner__
    def from_class_body
      @@method
    end
  end
end
