module IRB
  module TestHelper
    def self.without_rdoc(&block)
      ::Kernel.send(:alias_method, :old_require, :require)

      ::Kernel.define_method(:require) do |name|
        raise LoadError, "cannot load such file -- rdoc (test)" if name.match?("rdoc") || name.match?(/^rdoc\/.*/)
        ::Kernel.send(:old_require, name)
      end

      yield
    ensure
      EnvUtil.suppress_warning { ::Kernel.send(:alias_method, :require, :old_require) }
    end
  end
end
