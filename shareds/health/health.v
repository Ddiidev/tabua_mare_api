module health

import sync.stdatomic

pub struct State {
mut:
	ready         &stdatomic.AtomicVal[bool]
	shutting_down &stdatomic.AtomicVal[bool]
}

pub fn new_state() &State {
	return &State{
		ready:         stdatomic.new_atomic(false)
		shutting_down: stdatomic.new_atomic(false)
	}
}

pub fn (state &State) is_ready() bool {
	mut shutting_down := state.shutting_down
	if shutting_down.load() {
		return false
	}

	mut ready := state.ready
	return ready.load()
}

pub fn (state &State) mark_ready() {
	mut shutting_down := state.shutting_down
	if shutting_down.load() {
		return
	}

	mut ready := state.ready
	ready.store(true)
	if shutting_down.load() {
		ready.store(false)
	}
}

pub fn (state &State) begin_shutdown() {
	mut shutting_down := state.shutting_down
	shutting_down.store(true)

	mut ready := state.ready
	ready.store(false)
}
