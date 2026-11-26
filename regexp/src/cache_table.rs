//! The match cache table of `regexec.c`: a bit for each pair of a position
//! and a cache point, `num_cache_points * position + point`; a point inside a
//! look-around or an atomic group uses the next bit too. A table of up to
//! `FLAT_MAX_BITS` bits is a flat bit array. A larger one could be far too
//! large to allocate, so it is sparse, like a roaring bitmap: chunks of 2^16
//! bits, each a sorted array of the bits set until it has `CHUNK_ARRAY_MAX` of
//! them, then a bit array of 8 KB. Its memory follows the bits set, which the
//! work of the match bounds.

use std::collections::HashMap;
use std::hash::{BuildHasherDefault, Hasher};

const FLAT_MAX_BITS: usize = 1 << 29; // 64 MB
const CHUNK_BITS: u32 = 16;
const CHUNK_LEN: usize = (1 << CHUNK_BITS) / 8;
/// Smaller than the 4096 of roaring bitmaps, for the inserts into the array.
const CHUNK_ARRAY_MAX: usize = 512;

/// An allocation failed.
pub(crate) struct NoMemory;

enum Chunk {
    Array(Vec<u16>),
    Bits(Box<[u8]>),
}

/// `match_cache_slot`: the chunks are found by their key alone.
#[derive(Default)]
struct KeyHasher(u64);

impl Hasher for KeyHasher {
    fn finish(&self) -> u64 {
        self.0
    }

    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.write_u64((self.0 << 8) | u64::from(b));
        }
    }

    fn write_u64(&mut self, key: u64) {
        let h = key.wrapping_mul(0x9E37_79B9_7F4A_7C15);
        self.0 = h ^ (h >> 32);
    }

    fn write_i64(&mut self, key: i64) {
        self.write_u64(key as u64);
    }
}

enum Repr {
    Flat(Vec<u8>),
    Sparse(HashMap<i64, Chunk, BuildHasherDefault<KeyHasher>>),
}

pub(crate) struct MatchCacheTable(Repr);

impl Default for MatchCacheTable {
    fn default() -> Self {
        MatchCacheTable(Repr::Flat(Vec::new()))
    }
}

fn bits_test(bits: &[u8], i: usize) -> bool {
    (bits[i >> 3] >> (i & 7)) & 1 != 0
}

fn bits_set(bits: &mut [u8], i: usize) {
    bits[i >> 3] |= 1 << (i & 7);
}

fn zeroed(len: usize) -> Result<Vec<u8>, NoMemory> {
    let mut v = Vec::new();
    v.try_reserve_exact(len).map_err(|_| NoMemory)?;
    v.resize(len, 0);
    Ok(v)
}

impl MatchCacheTable {
    /// `match_cache_table_new`: the table for `num_bits` bits, and one more
    /// for the second bit of the last point.
    pub(crate) fn new(num_bits: usize) -> Result<Self, NoMemory> {
        if num_bits > FLAT_MAX_BITS {
            return Ok(MatchCacheTable(Repr::Sparse(HashMap::default())));
        }
        Ok(MatchCacheTable(Repr::Flat(zeroed(num_bits.div_ceil(8) + 1)?)))
    }

    pub(crate) fn test(&self, bit: i64) -> bool {
        match &self.0 {
            Repr::Flat(buf) => bits_test(buf, bit as usize),
            Repr::Sparse(chunks) => {
                let low = (bit & ((1 << CHUNK_BITS) - 1)) as u16;
                match chunks.get(&(bit >> CHUNK_BITS)) {
                    None => false,
                    Some(Chunk::Array(a)) => a.binary_search(&low).is_ok(),
                    Some(Chunk::Bits(b)) => bits_test(b, usize::from(low)),
                }
            }
        }
    }

    pub(crate) fn set(&mut self, bit: i64) -> Result<(), NoMemory> {
        let chunks = match &mut self.0 {
            Repr::Flat(buf) => {
                bits_set(buf, bit as usize);
                return Ok(());
            }
            Repr::Sparse(chunks) => chunks,
        };
        let key = bit >> CHUNK_BITS;
        let low = (bit & ((1 << CHUNK_BITS) - 1)) as u16;
        if !chunks.contains_key(&key) {
            chunks.try_reserve(1).map_err(|_| NoMemory)?;
        }
        let chunk = chunks.entry(key).or_insert(Chunk::Array(Vec::new()));
        let a = match chunk {
            Chunk::Bits(b) => {
                bits_set(b, usize::from(low));
                return Ok(());
            }
            Chunk::Array(a) => a,
        };
        let Err(i) = a.binary_search(&low) else { return Ok(()) };
        if a.len() == CHUNK_ARRAY_MAX {
            let mut b = zeroed(CHUNK_LEN)?;
            for &l in a.iter().chain([low].iter()) {
                bits_set(&mut b, usize::from(l));
            }
            *chunk = Chunk::Bits(b.into_boxed_slice());
            return Ok(());
        }
        if a.len() == a.capacity() {
            let capa = (a.capacity() * 2).clamp(4, CHUNK_ARRAY_MAX);
            a.try_reserve_exact(capa - a.len()).map_err(|_| NoMemory)?;
        }
        a.insert(i, low);
        Ok(())
    }
}
