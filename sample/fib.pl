   sub fib {
       local($n)=@_;
       if( $n<2 ){
           return $n;
       } {
           return &fib($n-2)+&fib($n-1)
       }
   }

   print &fib(20), "\n";
