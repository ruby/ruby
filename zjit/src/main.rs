#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct InsnId(usize);
#[derive(Copy, Clone, Eq, PartialEq, Hash, Debug)]
pub struct BlockId(usize);

enum Insn {
    Param { idx: usize },
}

#[derive(Debug)]
struct Block {
    params: Vec<InsnId>,
    insns: Vec<InsnId>,
}

#[derive(Debug)]
struct Function {
    name: String,
    entry_block: BlockId,
}

fn main() {
    println!("zjit");
}
