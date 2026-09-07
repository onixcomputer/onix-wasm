(module
  (import "env" "host_input" (func $input (result i32)))
  (memory (export "memory") 1)
  (func (export "prepareNickelStdlib")
    (drop (call $input))))
