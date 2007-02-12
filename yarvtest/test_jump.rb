require 'yarvtest/yarvtest'

class TestJump < YarvTestBase

  def test_redo
    ae %q{
      def m
        yield + 10
      end
      i=0
      m{
        if i>10
          i*i
        else
          i+=1
          redo
        end
      }
    }
  end

  def test_next
    ae %q{
      def m
        yield
        :ok
      end
      i=0
      m{
        if i>10
          i*i
        else
          i+=1
          next
        end
      }
    }
  end

  def test_next_with_val
    ae %q{
      def m
        yield
      end

      m{
        next :ok
      }
    }
  end
  
  def test_return
    ae %q{
      def m
        return 3
      end
      m
    }
    
    ae %q{
      def m
        :ng1
        mm{
          return :ok
        }
        :ng2
      end

      def mm
        :ng3
        yield
        :ng4
      end
      m
    }
  end

  def test_return2
    ae %q{
      $i = 0
      def m
        begin
          iter{
            return
          }
        ensure
          $i = 100
        end
      end
      
      def iter
        yield
      end
      m
      $i
    }
  end

  def test_return3
    ae %q{
      def m
        begin
          raise
        rescue
          return :ok
        end
        :ng
      end
      m
    }
  end
  
  def test_break
    ae %q{
      def m
        :ng1
        mm{
          yield
        }
        :ng2
      end

      def mm
        :ng3
        yield
        :ng4
      end

      m{
        break :ok
      }
    }
  end

  def test_exception_and_break
    ae %q{
      def m
        yield
      end
      
      m{
        begin
        ensure
          break :ok
        end
      }
    }
  end
  
  def test_retry
    # this test can't run on ruby 1.9(yarv can do)
    %q{
      def m a
        mm{
          yield
        }
      end

      def mm
        yield
      end

      i=0
      m(i+=1){
        retry if i<10
        :ok
      }
    }

    ae %q{
      def m a
        yield
      end
      
      i=0
      m(i+=1){
        retry if i<10
        :ok
      }
    }
  end

  def test_complex_jump
    ae %q{
      module Enumerable
        def all_?
          self.each{|e|
            unless yield(e)
              return false
            end
          }
          true
        end
      end

      xxx = 0
      [1,2].each{|bi|
        [3,4].each{|bj|
          [true, nil, true].all_?{|be| be}
          break
        }
        xxx += 1
      }
      xxx
    }
  end

  def test_return_from
    ae %q{
      def m
        begin
          raise
        rescue
          return 1
        end
      end
      
      m
    }
    ae %q{
      def m
        begin
          #
        ensure
          return 1
        end
      end
      
      m
    }
  end

  def test_break_from_times
    ae %q{
      3.times{
        break :ok
      }
    }
  end

  def test_catch_and_throw
    ae %q{
      catch(:foo){
        throw :foo
      }
    }
    ae %q{
      catch(:foo){
        throw :foo, false
      }
    }
    ae %q{
      catch(:foo){
        throw :foo, nil
      }
    }
    ae %q{
      catch(:foo){
        throw :foo, :ok
      }
    }
    ae %q{
      catch(:foo){
        1.times{
          throw :foo
        }
      }
    }
    ae %q{
      catch(:foo){
        1.times{
          throw :foo, :ok
        }
      }
    }
    ae %q{
      catch(:foo){
        catch(:bar){
          throw :foo, :ok
        }
        :ng
      }
    }
    ae %q{
      catch(:foo){
        catch(:bar){
          1.times{
            throw :foo, :ok
          }
        }
        :ng
      }
    }
  end
end

