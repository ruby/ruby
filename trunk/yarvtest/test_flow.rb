#
# This test program is contributed by   George Marrows
# Re: [Yarv-devel] Some tests	for test_jump.rb
#

require 'yarvtest/yarvtest'

class TestFlow < YarvTestBase
  def ae_flow(src, for_value=true)
    # Tracks flow through the code
    # A test like
    #   begin
    #   ensure
    #   end
    # gets transformed into
    #   a = []
    #   begin
    #     begin; a << 1
    #     ensure; a << 2
    #     end; a << 3
    #   rescue Exception
    #     a << 99
    #   end
    #   a
    # before being run. This tracks control flow through the code.
    
    cnt = 0
    src = src.gsub(/(\n|$)/) { "; $a << #{cnt+=1}\n" }
    src = "$a = []; begin; #{src}; rescue Exception; $a << 99; end; $a"
    
    if false#||true
      STDERR.puts
      STDERR.puts '#----'
      STDERR.puts src
      STDERR.puts '#----'
    end
    
    ae(src)
  end

  def test_while_with_ensure
    ae %q{
      a = []
      i = 0
      begin
        while i < 1
          i+=1
          begin
            begin
              next
            ensure
              a << :ok
            end
          ensure
            a << :ok2
          end
        end
      ensure
        a << :last
      end
    }
    ae %q{
      a = []
      i = 0
      begin
        while i < 1
          i+=1
          begin
            begin
              break
            ensure
              a << :ok
            end
          ensure
            a << :ok2
          end
        end
      ensure
        a << :last
      end
    }
    ae %q{
      a = []
      i = 0
      begin
        while i < 1
          if i>0
            break
          end
          i+=1
          begin
            begin
              redo
            ensure
              a << :ok
            end
          ensure
            a << :ok2
          end
        end
      ensure
        a << :last
      end
   }
  end
  
  def test_ensure_normal_flow
    ae_flow %{ 
      begin
      ensure
      end }
  end

  def test_ensure_exception
    ae_flow %{
      begin
        raise StandardError
      ensure
      end
    }
  end

  def test_break_in_block_runs_ensure
    ae_flow %{ 
      [1,2].each do
        begin
          break
        ensure
        end
      end
    }
  end

  def test_next_in_block_runs_ensure
    ae_flow %{ 
      [1,2].each do
        begin
          next
        ensure
        end
      end
    }
  end
  def test_return_from_method_runs_ensure
    ae_flow %{ 
      o = "test"
      def o.test(a)
        return a
      ensure
      end
      o.test(123)
    }
  end

  def test_break_from_ifunc
    ae %q{
      ["a"].inject("ng"){|x,y|
        break :ok
      }
    }
    ae %q{
      unless ''.respond_to? :lines
        class String
          def lines
            self
          end
        end
      end
      
      ('a').lines.map{|e|
        break :ok
      }
    }
    ae_flow %q{
      ["a"].inject("ng"){|x,y|
        break :ok
      }
    }
    ae_flow %q{
      ('a'..'b').map{|e|
        break :ok
      }
    }
  end
  
  def test_break_ensure_interaction1
    # make sure that any 'break state' set up in the VM is c
    # the time of the ensure
    ae_flow %{ 
      [1,2].each{
        break
      }
      begin
      ensure
      end
    }
  end
  
  def test_break_ensure_interaction2
    # ditto, different arrangement
    ae_flow %{ 
      begin
        [1,2].each do
          break
        end
      ensure
      end
    }
  end
  
  def test_break_through_2_ensures
    ae_flow %{ 
      [1,2].each do
        begin
          begin
            break
          ensure
          end
        ensure
        end
      end
    }
  end
  
  def test_ensure_break_ensure
    # break through an ensure; run 2nd normally
    ae_flow %{ 
      begin
        [1,2].each do
          begin
            break
          ensure
          end
        end
      ensure
      end
    }
  end
  
  def test_exception_overrides_break
    ae_flow %{ 
      [1,2].each do
        begin
          break
        ensure
          raise StandardError
        end
      end
    }
  end

  def test_break_overrides_exception
    ae_flow %{ 
      [1,2].each do
        begin
          raise StandardError
        ensure
          break
        end
      end
    }
    ae_flow %{ 
      [1,2].each do
        begin
          raise StandardError
        rescue
          break
        end
      end
    }
  end

  def test_break_in_exception
    ae_flow %q{
      i=0
      while i<3
        i+=1
        begin
        ensure
          break
        end
      end
    }
    ae_flow %q{
      i=0
      while i<3
        i+=1
        begin
          raise
        ensure
          break
        end
      end
    }
    ae_flow %q{
      i=0
      while i<3
        i+=1
        begin
          raise
        rescue
          break
        end
      end
    }
  end

  def test_next_in_exception
    return
    ae_flow %q{
      i=0
      while i<3
        i+=1
        begin
        ensure
          next
        end
      end
    }
    ae_flow %q{
      i=0
      while i<3
        i+=1
        begin
          raise
        ensure
          next
        end
      end
    }
    ae_flow %q{
      i=0
      while i<3
        i+=1
        begin
          raise
        rescue
          next
        end
      end
    }
  end

  def test_complex_break
    ae_flow %q{
      i = 0
      while i<3
        i+=1
        j = 0
        while j<3
          j+=1
          begin
            raise
          rescue
            break
          end
        end
      end
    }
    ae_flow %q{
      i = 0
      while i<3
        i+=1
        j = 0
        while j<3
          j+=1
          1.times{
            begin
              raise
            rescue
              break
            end
          }
        end
      end
    }
    ae_flow %q{
      i = 0
      while i<3
        i+=1
        j = 0
        while j<3
          j+=1
          begin
            raise
          ensure
            break
          end
        end
      end
    }
    ae_flow %q{
      i = 0
      while i<3
        i+=1
        j = 0
        while j<3
          j+=1
          1.times{
            begin
              raise
            ensure
              break
            end
          }
        end
      end
    }
    ae_flow %q{
      while true
        begin
          break
        ensure
          break
        end
      end
    }
    ae_flow %q{
      while true
        begin
          break
        ensure
          raise
        end
      end
    }
  end

  def test_jump_from_class
    ae_flow %q{
      3.times{
        class C
          break
        end
      }
    }
    ae_flow %q{
      3.times{
        class A
          class B
            break
          end
        end
      }
    }
    ae_flow %q{
      3.times{
        class C
          next
        end
      }
    }
    ae_flow %q{
      3.times{
        class C
          class D
            next
          end
        end
      }
    }
    ae_flow %q{
      while true
        class C
          break
        end
      end
    }
    ae_flow %q{
      while true
        class C
          class D
            break
          end
        end
      end
    }
    ae_flow %q{
      i=0
      while i<3
        i+=1
        class C
          next 10
        end
      end
    }
    ae %q{
      1.times{
        while true
          class C
            begin
              break
            ensure
              break
            end
          end
        end
      }
    }
  end

  def test_flow_with_cont_sp
    ae %q{
      def m a, b
        a + b
      end
      m(1,
        while true
          break 2
        end
        )
    }
    ae %q{
      def m a, b
        a + b
      end
      m(1,
        (i=0; while i<2
           i+=1
           class C
             next 2
           end
         end; 3)
        )
    }
    ae %q{
      def m a, b
        a+b
      end
      m(1, 1.times{break 3}) +
      m(10, (1.times{next 3}; 20))
    }
  end

  def test_return_in_deep_stack
    ae_flow %q{
      def m1 *args
        
      end
      def m2
        m1(:a, :b, (return 1; :c))
      end
      m2
    }
  end
  
  def test_return_in_ensure
    ae_flow %q{
      def m()
        begin
          2
        ensure
          return 3
        end
      end
      m
    }
    ae_flow %q{
      def m2
      end
      def m()
        m2(begin
             2
           ensure
             return 3
           end)
        4
      end
      m()
    }
    ae_flow %q{
      def m
        1
        1.times{
          2
          begin
            3
            return
            4
          ensure
            5
          end
          6
        }
        7
      end
      m()
    }
  end
end

