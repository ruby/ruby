
class Thread
  ## Transactional Variables

  # Make a transaction for TVar accesses.
  # You can nest Thread.atomically any times.
  #
  # Thread.atomically do
  #   tv1.value += 1
  #   Thread.atomically do # just ignore nested call
  #     tv2.value += tv1.value
  #   end
  # end
  #
  # If atomicity is violated, the given block will
  # be retried. Note that all side-effect except
  # `TVar#value=` will note be reverted.
  # So you should not call IO operations and so on.
  #
  def self.atomically
    if Primitive.tx_begin
      # fast commit
      begin
        while true
          ret = yield
          return ret if Primitive.tx_commit
          Primitive.tx_reset
        end
      rescue Thread::RetryTransaction
        Primitive.tx_reset
        retry
      ensure
        Primitive.tx_end
      end
    else
      yield
    end
  end

  # Ractor aware concurrent data structure.
  # TVar can only hold a shareable object.
  #
  class TVar
    def self.new init_value
      Primitive.tvar_new init_value
    end

    # Access to the value.
    #
    # You can access some values atomically with
    # Thread.atomically.
    #
    # tv1 = Thread::TVar.new(0)
    # tv2 = Thread::TVar.new(0)
    # Thread.atomically do
    #   tv1.value += 1
    #   tv2.value += 1
    # end
    #
    # On this example, other threads and ractors can observe
    # tv1.value == tv2.value within other transactions.
    #
    def value
      Primitive.tvar_value
    end

    # Set the value with val.
    #
    # Thread.atomically do
    #   tv1.value += 1
    # end
    #
    # val should be a shareable object.
    def value=(val)
      Primitive.tvar_value_set(val)
    end

    # Thread.atomically{ self.value += 1 }
    #
    def increment inc = 1
      Primitive.tvar_value_increment(inc)
    end

    def inspect
      index = Primitive.cexpr! %q{ tvar_slot_ptr(self)->index }
      value = Primitive.cexpr! %q{ tvar_slot_ptr(self)->value }
      "<TVar #{index} value:#{value}>"
    end

    private
    def __increment_any__ inc = 1
      Thread.atomically do
        self.value += inc
      end
    end
  end
end
