require "-test-/symbol"

module Test_Symbol
  module NonInterned
    module_function

    def noninterned_name(prefix = "")
      prefix += "_#{Thread.current.object_id.to_s(36).tr('-', '_')}"
      begin
        name = "#{prefix}_#{rand(0x1000).to_s(16)}_#{Time.now.usec}"
      end while Bug::Symbol.find(name)
      name
    end
  end
end
