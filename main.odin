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
// - [x]copy selected files to selected folder 
// - [ ] add -> commit -> push changes to repo 

SETTINGS_FILE :: "$HOME/.config/back_me_up/config.json"


AppData :: struct {
	copy_path: string,
	files:     [dynamic]FileDescriptor,
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
		wd, err := linux.inotify_add_watch(
			fd,
			strings.clone_to_cstring(expand_path(file.dir)),
			{.MODIFY},
		)
		if err != nil {
			fmt.eprintln("can't add file to watch")
			continue
		}
		file.wd = wd
	}

	for {
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

		handle_events(&event_queue, &app_data)
		// BUG: this stops program with no error werid
		//if err := run_git(expand_path(app_data.copy_path)); err != nil {
		//	log_err("crould not run git command", err)
		//}
	}

	defer for &file in app_data.files {
		linux.inotify_rm_watch(fd, file.wd)
	}
}

handle_events :: proc(event_queue: ^EventQueue, app_data: ^AppData) {
	for event in event_queue {
		log("copping")
		if file_d, ok := find_file_descriptor(app_data, event); ok {
			file_path := join_strings("", expand_path(file_d.dir), event.name)
			handle, err := os.open(file_path)
			defer os.close(handle)
			if err != nil {
				log_err("can't open in file", err)
			}
			data: [1024 * 100]byte
			i: int
			i, err = os.read(handle, data[:])
			if err != nil {
				log_err("can't read data", err)
			}
			copy_file_path := join_strings(
				"",
				expand_path(app_data.copy_path),
				file_d.save_destination,
				event.name,
			)
			dest_handle: os.Handle
			dest_handle, err = os.open(copy_file_path, os.O_RDWR)
			defer os.close(dest_handle)
			if err == os.ENOENT {
				if err := create_valid_path(
					expand_path(app_data.copy_path),
					file_d.save_destination,
					event.name,
				); err != nil {
					log_err("could not create valid path", err)
				}
			}
			dest_handle, err = os.open(copy_file_path, os.O_RDWR)
			if err != nil {
				log_err("can't open out file", err)
				continue
			}
			_, err = os.write(dest_handle, data[:i])
			if err != os.ERROR_NONE {
				log_err("can't write out file", err)
			}
		}
	}
}

create_valid_path :: proc(copy_dir, inner_dir, file: string) -> os.Error {
	if !os.is_dir_path(copy_dir) {
		panic("copy directory is not valid")
	}
	inner_dir_full := join_strings("", copy_dir, inner_dir)
	log(inner_dir_full)
	if !os.is_dir_path(inner_dir_full) {
		os.make_directory(inner_dir_full)
	}
	file_path_full := join_strings("", copy_dir, inner_dir, file)
	log(file_path_full)
	if !os.is_file_path(file_path_full) {
		handle := os.open(
			file_path_full,
			os.O_RDWR | os.O_CREATE | os.O_APPEND,
			os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IROTH,
		) or_return
		defer os.close(handle)
	}
	return nil
}

load_app_data :: proc(app_data: ^AppData) -> bool {
	data, ok := os.read_entire_file_from_filename(expand_path(SETTINGS_FILE))
	if !ok {
		fmt.eprintln("can't load file", expand_path(SETTINGS_FILE))
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

expand_path :: proc(path: string) -> string {
	s, _ := strings.replace(path, "$HOME", os.get_env("HOME"), 1)
	return s
}

run_git :: proc(repo_path: string) -> os.Error {
	log(repo_path)
	add_args := [?]string{"-C", repo_path, "add", "."}
	commit_args := [?]string{"-C", repo_path, "commit", "-m", "\'commit\'"}
	push_args := [?]string{"-C", repo_path, "push"}
	if err := os.execvp("git", add_args[:]); err != nil {
		return err
	}
	if err := os.execvp("git", add_args[:]); err != nil {
		return err
	}
	if err := os.execvp("git", add_args[:]); err != nil {
		return err
	}
	return nil
}
