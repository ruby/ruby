//! Named groups (the `NameTable` of regparse.c). Entries keep insertion
//! order like Ruby's st_table, which `Regexp#names` relies on.

use std::collections::HashMap;

#[derive(Clone, Debug)]
pub struct NameEntry {
    pub name: Vec<u8>,
    pub back_refs: Vec<i32>,
}

#[derive(Clone, Debug, Default)]
pub struct NameTable {
    entries: Vec<NameEntry>,
    index: HashMap<Vec<u8>, usize>,
}

impl NameTable {
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn entries(&self) -> &[NameEntry] {
        &self.entries
    }

    pub fn find(&self, name: &[u8]) -> Option<&NameEntry> {
        self.index.get(name).map(|&i| &self.entries[i])
    }

    /// Adds `backref` to `name`. Returns false when the name already has a
    /// group and `allow_multiplex` is false.
    pub fn add(&mut self, name: &[u8], backref: i32, allow_multiplex: bool) -> bool {
        let i = match self.index.get(name) {
            Some(&i) => i,
            None => {
                self.entries.push(NameEntry { name: name.to_vec(), back_refs: Vec::new() });
                self.index.insert(name.to_vec(), self.entries.len() - 1);
                self.entries.len() - 1
            }
        };
        let e = &mut self.entries[i];
        if !e.back_refs.is_empty() && !allow_multiplex {
            return false;
        }
        e.back_refs.push(backref);
        true
    }

    /// `onig_renumber_name_table`: `map[old] = new`.
    pub fn renumber(&mut self, map: &[i32]) {
        for e in self.entries.iter_mut() {
            for r in e.back_refs.iter_mut() {
                *r = map[*r as usize];
            }
        }
    }

    pub fn memsize(&self) -> usize {
        self.entries.iter().map(|e| e.name.len() * 2 + e.back_refs.len() * 4 + 64).sum()
    }
}
