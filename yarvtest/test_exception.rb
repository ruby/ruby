require 'yarvtest/yarvtest'

class TestException < YarvTestBase

  def test_rescue
    ae %q{
      begin
        1
      rescue
        2
      end
    }

    ae %q{
      begin
        1
        begin
          2
        rescue
          3
        end
        4
      rescue
        5
      end
    }

    ae %q{
      begin
        1
      rescue
        2
      else
        3
      end
    }
  end

  def test_ensure
    ae %q{
      begin
        1+1
      ensure
        2+2
      end
    }
    ae %q{
      begin
        1+1
        begin
          2+2
        ensure
          3+3
        end
      ensure
        4+4
      end
    }
    ae %q{
      begin
        1+1
        begin
          2+2
        ensure
          3+3
        end
      ensure
        4+4
        begin
          5+5
        ensure
          6+6
        end
      end
    }
  end

  def test_rescue_ensure
    ae %q{
      begin
        1+1
      rescue
        2+2
      ensure
        3+3
      end
   }
    ae %q{
      begin
        1+1
      rescue
        2+2
      ensure
        3+3
      end
   }
    ae %q{
      begin
        1+1
      rescue
        2+2
      else
        3+3
      ensure
        4+4
      end
   }
   ae %q{
     begin
       1+1
       begin
         2+2
       rescue
         3+3
       else
         4+4
       end
     rescue
       5+5
     else
       6+6
     ensure
       7+7
     end
   }
   
  end

  def test_raise
    ae %q{
      begin
        raise
      rescue
        :ok
      end
    }
    ae %q{
      begin
        raise
      rescue
        :ok
      ensure
        :ng
      end
    }
    ae %q{
      begin
        raise
      rescue => e
        e.class
      end
    }
    ae %q{
      begin
        raise
      rescue StandardError
        :ng
      rescue Exception
        :ok
      end
    }
    ae %q{
      begin
        begin
          raise "a"
        rescue
          raise "b"
        ensure
          raise "c"
        end
      rescue => e
        e.message
      end
    }
  end

  def test_error_variable
    ae %q{
      a = nil
      1.times{|e|
        begin
        rescue => err
        end
        a = err.class
      }
    }
    ae %q{
      a = nil
      1.times{|e|
        begin
          raise
        rescue => err
        end
        a = err.class
      }
      a
    }
  end
  
  def test_raise_in_other_scope
    ae %q{
      class E1 < Exception
      end
      
      def m
        yield
      end
      
      begin
        begin
          begin
            m{
              raise
            }
          rescue E1
            :ok2
          ensure
          end
        rescue
          :ok3
        ensure
        end
      rescue E1
        :ok
      ensure
      end
    } do
      remove_const :E1
    end

    ae %q{
      $i = 0
      def m
        iter{
          begin
            $i += 1
            begin
              $i += 2
              break
            ensure
              
            end
          ensure
            $i += 4
          end
          $i = 0
        }
      end
      
      def iter
        yield
      end
      m
      $i
    }

    ae %q{
      $i = 0
      def m
        begin
          $i += 1
          begin
            $i += 2
            return
          ensure
            $i += 3
          end
        ensure
          $i += 4
        end
        p :end
      end
      m
      $i
    }
  end

  def test_raise_in_cont_sp
    ae %q{
      def m a, b
        a + b
      end
      m(1, begin
             raise
           rescue
             2
           end) +
      m(10, begin
             raise
           rescue
             20
           ensure
             30
           end)
    }
    ae %q{
      def m a, b
        a + b
      end
      m(begin
          raise
        rescue
          1
        end,
        begin
          raise
        rescue
          2
        end)
    }
  end

  def test_geterror
    ae %q{
      $!
    }
    ae %q{
      begin
        raise "FOO"
      rescue
        $!
      end
    }
    ae %q{
      def m
        $!
      end
      begin
        raise "FOO"
      rescue
        m()
      end
    }
    ae %q{
      $ans = []
      def m
        $!
      end
      begin
        raise "FOO"
      rescue
        begin
          raise "BAR"
        rescue
          $ans << m()
        end
        $ans << m()
      end
      $ans
    }
    ae %q{
      $ans = []
      def m
        $!
      end
      
      begin
        begin
          raise "FOO"
        ensure
          $ans << m()
        end
      rescue
        $ans << m()
      end
    }
    ae %q{
      $ans = []
      def m
        $!
      end
      def m2
        1.times{
          begin
            return
          ensure
            $ans << m
          end
        }
      end
      m2
      $ans
    }
  end

  def test_stack_consistency
    ae %q{ # 
      proc{
        begin
          raise
          break
        rescue
          :ok
        end
      }.call
    }
    ae %q{
      proc do
        begin
          raise StandardError
          redo
        rescue StandardError
        end
      end.call
    }
  end
end

