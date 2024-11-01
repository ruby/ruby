use std::collections::VecDeque;
use std::marker::PhantomData;

use crate::mmtk;
use crate::upcalls;
use crate::Ruby;
use mmtk::util::opaque_pointer::*;
use mmtk::vm::ActivePlan;
use mmtk::Mutator;

pub struct VMActivePlan {}

impl ActivePlan<Ruby> for VMActivePlan {
    fn number_of_mutators() -> usize {
        (upcalls().number_of_mutators)()
    }

    fn is_mutator(_tls: VMThread) -> bool {
        (upcalls().is_mutator)()
    }

    fn mutator(_tls: VMMutatorThread) -> &'static mut Mutator<Ruby> {
        unimplemented!()
    }

    fn mutators<'a>() -> Box<dyn Iterator<Item = &'a mut Mutator<Ruby>> + 'a> {
        let mut mutators = VecDeque::new();
        (upcalls().get_mutators)(
            add_mutator_to_vec,
            &mut mutators as *mut VecDeque<&mut Mutator<Ruby>> as _,
        );

        Box::new(RubyMutatorIterator {
            mutators,
            phantom_data: PhantomData,
        })
    }
}

extern "C" fn add_mutator_to_vec(mutator: *mut Mutator<Ruby>, mutators: *mut libc::c_void) {
    let mutators = unsafe { &mut *(mutators as *mut VecDeque<*mut Mutator<Ruby>>) };
    mutators.push_back(unsafe { &mut *mutator });
}

struct RubyMutatorIterator<'a> {
    mutators: VecDeque<&'a mut Mutator<Ruby>>,
    phantom_data: PhantomData<&'a ()>,
}

impl<'a> Iterator for RubyMutatorIterator<'a> {
    type Item = &'a mut Mutator<Ruby>;

    fn next(&mut self) -> Option<Self::Item> {
        self.mutators.pop_front()
    }
}
