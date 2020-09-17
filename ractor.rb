class Ractor
  # Create a new Ractor with args and a block.
  # args are passed via incoming channel.
  # A block (Proc) will be isolated (can't acccess to outer variables)
  #
  # A ractor has default two channels:
  # an incoming channel and an outgoing channel.
  #
  # Other ractors send objects to the ractor via the incoming channel and
  # the ractor receives them.
  # The ractor send objects via the outgoing channel and other ractors can
  # receive them.
  #
  # The result of the block is sent via the outgoing channel
  # and other 
  #
  # r = Ractor.new do
  #   Ractor.recv    # recv via r's mailbox => 1
  #   Ractor.recv    # recv via r's mailbox => 2
  #   Ractor.yield 3 # yield a message (3) and wait for taking by another ractor.
  #   'ok'           # the return value will be yielded.
  #                  # and r's incoming/outgoing ports are closed automatically.
  # end
  # r.send 1 # send a message (1) into r's mailbox.
  # r <<   2 # << is an alias of `send`.
  # p r.take   # take a message from r's outgoing port #=> 3
  # p r.take   #                                        => 'ok'
  # p r.take   # raise Ractor::ClosedError
  #
  # other options:
  #   name: Ractor's name
  # 
  def self.new *args, name: nil, &block
    b = block # TODO: builtin bug
    raise ArgumentError, "must be called with a block" unless block
    loc = caller_locations(1, 1).first
    loc = "#{loc.path}:#{loc.lineno}"
    __builtin_ractor_create(loc, name, args, b)
  end

  # return current Ractor
  def self.current
    __builtin_cexpr! %q{
      rb_ec_ractor_ptr(ec)->self
    }
  end

  def self.count
    __builtin_cexpr! %q{
      ULONG2NUM(GET_VM()->ractor.cnt);
    }
  end

  # Multiplex multiple Ractor communications.
  #
  # r, obj = Ractor.select(r1, r2)
  # #=> wait for taking from r1 or r2
  # #   returned obj is a taken object from Ractor r
  #
  # r, obj = Ractor.select(r1, r2, Ractor.current)
  # #=> wait for taking from r1 or r2
  # #         or recv from incoming queue
  # #   If recv is succeed, then obj is received value
  # #   and r is :recv (Ractor.current)
  #
  # r, obj = Ractor.select(r1, r2, Ractor.current, yield_value: obj)
  # #=> wait for taking from r1 or r2
  # #         or recv from incoming queue
  # #         or yield (Ractor.yield) obj
  # #   If yield is succeed, then obj is nil
  # #   and r is :yield
  #
  def self.select *ractors, yield_value: yield_unspecified = true, move: false
    __builtin_cstmt! %q{
      const VALUE *rs = RARRAY_CONST_PTR_TRANSIENT(ractors);
      VALUE rv;
      VALUE v = ractor_select(ec, rs, RARRAY_LENINT(ractors),
                              yield_unspecified == Qtrue ? Qundef : yield_value,
                              (bool)RTEST(move) ? true : false, &rv);
      return rb_ary_new_from_args(2, rv, v);
    }
  end

  # Receive an incoming message from Ractor's incoming queue.
  def self.recv
    __builtin_cexpr! %q{
      ractor_recv(ec, rb_ec_ractor_ptr(ec))
    }
  end

  private def recv
    __builtin_cexpr! %q{
      // TODO: check current actor
      ractor_recv(ec, RACTOR_PTR(self))
    }
  end

  # Send a message to a Ractor's incoming queue.
  #
  # # Example:
  #   r = Ractor.new do
  #     p Ractor.recv #=> 'ok'
  #   end
  #   r.send 'ok' # send to r's incoming queue.
  def send obj, move: false
    __builtin_cexpr! %q{
      ractor_send(ec, RACTOR_PTR(self), obj, move)
    }
  end

  # yield a message to the ractor's outgoing port.
  def self.yield obj, move: false
    __builtin_cexpr! %q{
      ractor_yield(ec, rb_ec_ractor_ptr(ec), obj, move)
    }
  end

  # Take a message from ractor's outgoing port.
  #
  # Example:
  #   r = Ractor.new{ 'oK' }
  #   p r.take #=> 'ok'
  def take
    __builtin_cexpr! %q{
      ractor_take(ec, RACTOR_PTR(self))
    }
  end

  alias << send

  def inspect
    loc  = __builtin_cexpr! %q{ RACTOR_PTR(self)->loc }
    name = __builtin_cexpr! %q{ RACTOR_PTR(self)->name }
    id   = __builtin_cexpr! %q{ INT2FIX(RACTOR_PTR(self)->id) }
    "#<Ractor:##{id}#{name ? ' '+name : ''}#{loc ? " " + loc : ''}>"
  end

  def name
    __builtin_cexpr! %q{ RACTOR_PTR(self)->name }
  end

  def name=(new_name)
    __builtin_cexpr! %q{ rb_actor_setname(RACTOR_PTR(self), new_name) }
  end


  # Returns the status of a +ractor+.
  #
  # [<tt>"created"</tt>]
  #	Returned if a ractor has just been created and not ready to run
  # [<tt>"blocking"</tt>]
  #	Returned if all threads are blocking
  # [<tt>"running"</tt>]
  #	When any thread of a ractor is running
  # [<tt>"terminated"</tt>]
  #	Return if a ractor finishes its execution
  def status
    __builtin_cexpr! %q{
      rb_str_new2(ractor_status_str(RACTOR_PTR(self)->status_))
    }
  end

  class RemoteError
    attr_reader :ractor
  end

  def close_incoming
    __builtin_cexpr! %q{
      ractor_close_incoming(ec, RACTOR_PTR(self));
    }
  end

  def close_outgoing
    __builtin_cexpr! %q{
      ractor_close_outgoing(ec, RACTOR_PTR(self));
    }
  end

  def close
    close_incoming
    close_outgoing
  end
end
