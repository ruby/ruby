// This file came from here: https://github.com/bboissin/thesis_bboissin/blob/main/src/algorithm13.rs
//
// Copyright (c) 2025 bboissin
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// It's also Apache-2.0 licensed
use std::hash::Hash;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Ord, PartialOrd)]
pub struct Register(pub u32);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Ord, PartialOrd)]
pub struct RegisterCopy {
    pub source: Register,
    pub destination: Register,
}

// Algorithm 13: Parallel copy sequentialization
//
// Takes a list of parallel copies, return a list of sequential copy operations
// such that each output register contains the same value as if the copies were
// parallel.
// The `spare` register may be used to break cycles and should not be contained
// in `parallel_copies`. The value of `spare` is undefined after the function
// returns.
//
// Varies slightly from the original algorithm as it splits the copies between
// pending and available to reduce state tracking.
pub fn sequentialize_register(parallel_copies: &[RegisterCopy], spare: Register) -> Vec<RegisterCopy> {
    let mut sequentialized = Vec::new();
    // `resource` in the original code, this point to the current register
    // holding a particular initial value.
    // If a given Register is no longer needed, the value might be inaccurate.
    let mut current_holder = std::collections::HashMap::new();
    // Copies that are pending, indexed by destination register.
    // Use btree map to stay deterministic.
    let mut pending = std::collections::BTreeMap::new();
    // If a copy can be materialized (nothing depends on the destination), we
    // move it from pending into available.
    let mut available = Vec::new();

    for copy in parallel_copies {
        if copy.source == spare || copy.destination == spare {
            panic!("Spare register cannot be a source or destination of a copy");
        }
        if let Some(_old_value) = pending.insert(copy.destination, copy) {
            panic!(
                "Destination register {:?} has multiple copies.",
                copy.destination
            );
        }
        current_holder.insert(copy.source, copy.source);
    }
    for copy in parallel_copies {
        // If we didn't record it, this means nothing depends on that register.
        if !current_holder.contains_key(&copy.destination) {
            pending.remove(&copy.destination);
            available.push(copy);
        }
    }
    while !pending.is_empty() || !available.is_empty() {
        while let Some(copy) = available.pop() {
            if let Some(source) = current_holder.get_mut(&copy.source) {
                // Materialize the copy.
                sequentialized.push(RegisterCopy {
                    source: source.clone(),
                    destination: copy.destination,
                });
                if let Some(available_copy) = pending.remove(source) {
                    available.push(available_copy);
                    // Point to the new destination.
                    *source = copy.destination;
                } else if *source == spare {
                    // Also point to new destination if we were copying from a
                    // spare, this lets us reuse spare for the next cycle.
                    *source = copy.destination;
                }
            } else {
                panic!("No holder for source register {:?}", copy.source);
            }
        }
        // If we have anything left, break the cycle by using the spare register
        // on the first pending entry.
        if let Some((destination, copy)) = pending.iter().next() {
            sequentialized.push(RegisterCopy {
                source: copy.destination,
                destination: spare,
            });
            current_holder.insert(copy.destination, spare);
            available.push(copy);
            let to_remove = *destination;
            pending.remove(&to_remove);
        } else {
            // nothing pending.
            break;
        }
    }
    sequentialized
}

#[cfg(test)]
mod tests {
    use rand::Rng;
    use std::collections::HashMap;

    use super::*;
    use assert_matches::assert_matches;

    // Assumes that each register initially contains the value matching its id.
    fn execute_sequential(copies: &[RegisterCopy]) -> HashMap<Register, u32> {
        let mut register_values = HashMap::new();
        // Initialize registers with their own ids as values.
        for copy in copies {
            register_values.insert(copy.source, copy.source.0);
        }
        for copy in copies {
            let source_value = *register_values.get(&copy.source).unwrap();
            register_values.insert(copy.destination, source_value);
        }
        register_values
    }

    fn execute_parallel(copies: &[RegisterCopy]) -> HashMap<Register, u32> {
        let mut register_values = HashMap::new();
        // Initialize registers with their own ids as values.
        for copy in copies {
            register_values.insert(copy.source, copy.source.0);
        }
        // Execute copies.
        for copy in copies {
            register_values.insert(copy.destination, copy.source.0);
        }
        register_values
    }

    #[test]
    fn test_execute_sequential() {
        let copies = vec![
            RegisterCopy {
                source: Register(1),
                destination: Register(2),
            },
            RegisterCopy {
                source: Register(3),
                destination: Register(2),
            },
            RegisterCopy {
                source: Register(2),
                destination: Register(4),
            },
            RegisterCopy {
                source: Register(2),
                destination: Register(1),
            },
            RegisterCopy {
                source: Register(5),
                destination: Register(3),
            },
        ];
        let result = execute_sequential(&copies);
        let expected: HashMap<Register, u32> = vec![
            (Register(1), 3),
            (Register(2), 3),
            (Register(3), 5),
            (Register(4), 3),
            (Register(5), 5),
        ]
        .into_iter()
        .collect();
        assert_eq!(result, expected);
    }

    #[test]
    fn test_execute_sequential_2() {
        let copies = vec![
            RegisterCopy {
                source: Register(1),
                destination: Register(4),
            },
            RegisterCopy {
                source: Register(3),
                destination: Register(1),
            },
            RegisterCopy {
                source: Register(2),
                destination: Register(3),
            },
            RegisterCopy {
                source: Register(1),
                destination: Register(2),
            },
        ];
        let result = execute_sequential(&copies);
        assert_eq!(
            result,
            Vec::from_iter([
                (Register(1), 3),
                (Register(2), 3),
                (Register(3), 2),
                (Register(4), 1),
            ])
            .into_iter()
            .collect::<HashMap<_, _>>()
        );
    }

    #[test]
    fn test_sequentialize_register_simple() {
        let copies = vec![
            RegisterCopy {
                source: Register(1),
                destination: Register(2),
            },
            RegisterCopy {
                source: Register(2),
                destination: Register(3),
            },
            RegisterCopy {
                source: Register(3),
                destination: Register(4),
            },
        ];

        let spare = Register(5);
        let result = sequentialize_register(&copies, spare);
        let sequential_result = execute_sequential(&result);
        assert_eq!(
            sequential_result,
            Vec::from_iter([
                (Register(1), 1),
                (Register(2), 1),
                (Register(3), 2),
                (Register(4), 3),
            ])
            .into_iter()
            .collect::<HashMap<_, _>>()
        );
    }

    #[test]
    fn test_sequentialize_cycle() {
        let copies = vec![
            RegisterCopy {
                source: Register(1),
                destination: Register(2),
            },
            RegisterCopy {
                source: Register(2),
                destination: Register(3),
            },
            RegisterCopy {
                source: Register(3),
                destination: Register(1),
            },
        ];
        let spare = Register(4);
        let result = sequentialize_register(&copies, spare);
        let mut sequential_result = execute_sequential(&result);
        assert_matches!(sequential_result.remove(&spare), Some(_));
        assert_eq!(
            sequential_result,
            Vec::from_iter([(Register(2), 1), (Register(3), 2), (Register(1), 3),])
                .into_iter()
                .collect::<HashMap<_, _>>()
        );
    }

    #[test]
    fn test_sequentialize_no_pending() {
        let copies = vec![
            RegisterCopy {
                source: Register(1),
                destination: Register(2),
            },
            RegisterCopy {
                source: Register(3),
                destination: Register(4),
            },
        ];
        let spare = Register(5);
        let result = sequentialize_register(&copies, spare);
        let sequential_result = execute_sequential(&result);
        assert_eq!(
            sequential_result,
            Vec::from_iter([
                (Register(1), 1),
                (Register(2), 1),
                (Register(3), 3),
                (Register(4), 3),
            ])
            .into_iter()
            .collect::<HashMap<_, _>>()
        );
    }

    #[test]
    fn test_sequentialize_with_fanin() {
        let copies = vec![
            RegisterCopy {
                source: Register(1),
                destination: Register(2),
            },
            RegisterCopy {
                source: Register(1),
                destination: Register(3),
            },
            RegisterCopy {
                source: Register(2),
                destination: Register(1),
            },
        ];
        let spare = Register(4);
        let result = sequentialize_register(&copies, spare);
        let sequential_result = execute_sequential(&result);
        assert_eq!(
            sequential_result,
            Vec::from_iter([(Register(2), 1), (Register(3), 1), (Register(1), 2)])
                .into_iter()
                .collect::<HashMap<_, _>>()
        );
    }

    #[test]
    fn test_sequentialize_rand() {
        let mut rng = rand::rng();
        for _ in 0..1000 {
            let num_copies = 100;
            let mut copies = Vec::new();
            for i in 0..num_copies {
                let dest = Register(i);
                let src = Register(rng.random_range(0..num_copies));
                if src == dest {
                    continue; // Skip self-copies
                }
                copies.push(RegisterCopy {
                    source: src,
                    destination: dest,
                });
            }
            // shuffle the copies.
            use rand::seq::SliceRandom;

            copies.shuffle(&mut rng);
            let spare = Register(num_copies);
            let result = sequentialize_register(&copies, spare);
            let mut sequential_result = execute_sequential(&result);
            // remove the spare register from the result.
            sequential_result.remove(&spare);
            assert_eq!(sequential_result, execute_parallel(&copies));
        }
    }
}
