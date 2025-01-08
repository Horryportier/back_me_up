package main

import "core:fmt"
import "core:strings"


has :: proc(array: $T/[dynamic]$E, item: E) -> bool {
	for i in array {
		if i == item {
			return true
		}
	}
	return false
}

log :: proc(stuff: ..any) {
	for s in stuff {
		fmt.print(s, "")
	}
	fmt.println()
}

log_err :: proc(stuff: ..any) {
	for s in stuff {
		fmt.eprint(s, "")
	}
	fmt.eprintln()
}

join_strings :: proc(sep: string, strs: ..string) -> string {
	arr: [dynamic]string
	for s in strs {
		append(&arr, s)
	}
	return strings.join(arr[:], sep)
}
