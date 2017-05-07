require 'mspec/expectations/expectations'

class Object
  alias_method :__mspec_object_id__, :object_id
end

module Mock
  def self.reset
    @mocks = @stubs = @objects = nil
  end

  def self.objects
    @objects ||= {}
  end

  def self.mocks
    @mocks ||= Hash.new { |h,k| h[k] = [] }
  end

  def self.stubs
    @stubs ||= Hash.new { |h,k| h[k] = [] }
  end

  def self.replaced_name(obj, sym)
    :"__mspec_#{obj.__mspec_object_id__}_#{sym}__"
  end

  def self.replaced_key(obj, sym)
    [replaced_name(obj, sym), sym]
  end

  def self.has_key?(keys, sym)
    !!keys.find { |k| k.first == sym }
  end

  def self.replaced?(sym)
    has_key?(mocks.keys, sym) or has_key?(stubs.keys, sym)
  end

  def self.clear_replaced(key)
    mocks.delete key
    stubs.delete key
  end

  def self.mock_respond_to?(obj, sym, include_private = false)
    name = replaced_name(obj, :respond_to?)
    if replaced? name
      obj.__send__ name, sym, include_private
    else
      obj.respond_to? sym, include_private
    end
  end

  def self.install_method(obj, sym, type=nil)
    meta = obj.singleton_class

    key = replaced_key obj, sym
    sym = sym.to_sym

    if (sym == :respond_to? or mock_respond_to?(obj, sym, true)) and !replaced?(key.first)
      meta.__send__ :alias_method, key.first, sym
    end

    meta.class_eval {
      define_method(sym) do |*args, &block|
        Mock.verify_call self, sym, *args, &block
      end
    }

    proxy = MockProxy.new type

    if proxy.mock?
      MSpec.expectation
      MSpec.actions :expectation, MSpec.current.state
    end

    if proxy.stub?
      stubs[key].unshift proxy
    else
      mocks[key] << proxy
    end
    objects[key] = obj

    proxy
  end

  def self.name_or_inspect(obj)
    obj.instance_variable_get(:@name) || obj.inspect
  end

  def self.verify_count
    mocks.each do |key, proxies|
      obj = objects[key]
      proxies.each do |proxy|
        qualifier, count = proxy.count
        pass = case qualifier
        when :at_least
          proxy.calls >= count
        when :at_most
          proxy.calls <= count
        when :exactly
          proxy.calls == count
        when :any_number_of_times
          true
        else
          false
        end
        unless pass
          SpecExpectation.fail_with(
            "Mock '#{name_or_inspect obj}' expected to receive '#{key.last}' " + \
            "#{qualifier.to_s.sub('_', ' ')} #{count} times",
            "but received it #{proxy.calls} times")
        end
      end
    end
  end

  def self.verify_call(obj, sym, *args, &block)
    compare = *args
    compare = compare.first if compare.length <= 1

    key = replaced_key obj, sym
    [mocks, stubs].each do |proxies|
      proxies[key].each do |proxy|
        pass = case proxy.arguments
        when :any_args
          true
        when :no_args
          compare.nil?
        else
          proxy.arguments == compare
        end

        if proxy.yielding?
          if block
            proxy.yielding.each do |args_to_yield|
              if block.arity == -1 || block.arity == args_to_yield.size
                block.call(*args_to_yield)
              else
                SpecExpectation.fail_with(
                  "Mock '#{name_or_inspect obj}' asked to yield " + \
                  "|#{proxy.yielding.join(', ')}| on #{sym}\n",
                  "but a block with arity #{block.arity} was passed")
              end
            end
          else
            SpecExpectation.fail_with(
              "Mock '#{name_or_inspect obj}' asked to yield " + \
              "|[#{proxy.yielding.join('], [')}]| on #{sym}\n",
              "but no block was passed")
          end
        end

        if pass
          proxy.called

          if proxy.raising?
            raise proxy.raising
          else
            return proxy.returning
          end
        end
      end
    end

    if sym.to_sym == :respond_to?
      mock_respond_to? obj, compare
    else
      SpecExpectation.fail_with("Mock '#{name_or_inspect obj}': method #{sym}\n",
                            "called with unexpected arguments (#{Array(compare).join(' ')})")
    end
  end

  def self.cleanup
    objects.each do |key, obj|
      if obj.kind_of? MockIntObject
        clear_replaced key
        next
      end

      replaced = key.first
      sym = key.last
      meta = obj.singleton_class

      if mock_respond_to? obj, replaced, true
        meta.__send__ :alias_method, sym, replaced
        meta.__send__ :remove_method, replaced
      else
        meta.__send__ :remove_method, sym
      end

      clear_replaced key
    end
  ensure
    reset
  end
end
