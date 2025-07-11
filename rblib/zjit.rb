module RubyVM::ZJIT
  # Assert that any future ZJIT compilation will return a function pointer
  def self.assert_compiles
    Primitive.rb_zjit_assert_compiles
  end
end
