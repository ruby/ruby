use crate::Ruby;
use mmtk::util::ObjectReference;
use mmtk::util::VMWorkerThread;
use mmtk::vm::ReferenceGlue;

pub struct VMReferenceGlue {}

impl ReferenceGlue<Ruby> for VMReferenceGlue {
    type FinalizableType = ObjectReference;

    fn get_referent(_object: ObjectReference) -> Option<ObjectReference> {
        unimplemented!()
    }

    fn set_referent(_reff: ObjectReference, _referent: ObjectReference) {
        unimplemented!()
    }

    fn enqueue_references(_references: &[ObjectReference], _tls: VMWorkerThread) {
        unimplemented!()
    }

    fn clear_referent(_new_reference: ObjectReference) {
        unimplemented!()
    }
}
