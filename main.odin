package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:sys/linux"

// NOTE: GOAL 
// - [x] watch selected files for changes 
// - [?]copy selected files to selected folder 
// - [ ] add -> commit -> push changes to repo 

SETTINGS_FILE :: "test.json"


AppData :: struct {
	files: [dynamic]FileDescriptor,
}

FileDescriptor :: struct {
	wd:               linux.Wd,
	dir:              string,
	files:            [dynamic]string,
	save_destination: string,
}

Event :: struct {
	wd:   linux.Wd,
	name: string,
}

EventQueue :: [dynamic]Event

main :: proc() {
	app_data: AppData
	event_queue: EventQueue
	if !load_app_data(&app_data) {
		fmt.eprintln("can't load AppData")
		return
	}
	fd, err := linux.inotify_init()
	defer linux.close(fd)
	if err != nil {
		fmt.eprintln("can't init inotfiy")
		return
	}

	for &file in app_data.files {
		wd, err := linux.inotify_add_watch(fd, strings.clone_to_cstring(file.dir), {.MODIFY})
		if err != nil {
			fmt.eprintln("can't add file to watch")
			continue
		}
		file.wd = wd
	}

	for {
		buff: [4096]u8
		length: int
		fmt.println("readinig event")
		length, err = linux.read(fd, buff[:])
		if err != nil {
			fmt.eprintln("can't read event", err)
		}
		for offset := 0; offset < length; {
			event := cast(^linux.Inotify_Event)&buff[offset]
			name := string(slice.bytes_from_ptr(&event.name, int(event.len)))
			offset += size_of(linux.Inotify_Event) + len(name)
			name, _ = strings.replace(name, "\x00", "", 1000)
			append(&event_queue, Event{event.wd, name})
		}

		for event in event_queue {
			log("copping")
			if file_d, ok := find_file_descriptor(&app_data, event); ok {
				f := [?]string{file_d.dir, event.name}
				handle, err := os.open(strings.join(f[:], ""))
				defer os.close(handle)
				if err != nil {
					log_err("can't open file", err)
				}
				data: [1024 * 4]byte
				i: int
				i, err = os.read(handle, data[:])
				if err != nil {
					log_err("can't read data", err)
				}
				f = [?]string{file_d.save_destination, event.name}
				dest_handle: os.Handle
				dest_handle, err = os.open(strings.join(f[:], ""), os.O_RDWR)
				defer os.close(dest_handle)
				// BUG: if directory or file dose not exsitst it will break
				if err != nil {
					log_err("can't open file", err)
				}
				os.write(dest_handle, data[:i])
			}
		}
	}

	defer for &file in app_data.files {
		linux.inotify_rm_watch(fd, file.wd)
	}
}

load_app_data :: proc(app_data: ^AppData) -> bool {
	data, ok := os.read_entire_file_from_filename(SETTINGS_FILE)
	if !ok {
		fmt.eprintln("can't load file", SETTINGS_FILE)
		return false
	}
	defer delete(data)
	err := json.unmarshal(data, app_data)
	if err != nil {
		fmt.eprintln("can't unmarshal json", err)
		return false
	}
	return true
}

find_file_descriptor :: proc(app_data: ^AppData, event: Event) -> (FileDescriptor, bool) {
	for file in app_data.files {
		if file.wd == event.wd && has(file.files, event.name) {
			return file, true
		}
	}
	return FileDescriptor{}, false
}

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
