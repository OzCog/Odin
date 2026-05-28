// OdinCog - AIGLA (Active Inference Game Loop Agent)
// World State Container
//
// This module implements immutable world state snapshots with copy-on-write
// semantics. The world state encapsulates the entire cognitive system state
// including AtomSpace, attention values, and inference state.

package odincog_world_state

import "core:mem"
import "core:time"
import "core:sync"
import "core:fmt"
import "core:slice"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"
import "../memory"

// =============================================================================
// WORLD STATE TYPES
// =============================================================================

// StateVersion tracks state changes
StateVersion :: u64

// StateChecksum for integrity verification
StateChecksum :: u64

// TransactionID uniquely identifies a state mutation
TransactionID :: u64

// =============================================================================
// WORLD STATE SNAPSHOT
// =============================================================================

// WorldState represents an immutable snapshot of the entire system state
WorldState :: struct {
    // Identity
    version:            StateVersion,
    timestamp:          time.Time,
    tick:               u64,
    
    // Reference to live AtomSpace
    atomspace:          ^atomspace.AtomSpace,
    
    // Snapshot data (for checkpointing)
    snapshot:           ^StateSnapshot,
    
    // Attention state summary
    attention_summary:  AttentionSummary,
    
    // Inference state
    inference_state:    InferenceSnapshot,
    
    // Transaction log since last snapshot
    transactions:       [dynamic]Transaction,
    
    // Metadata
    checksum:           StateChecksum,
    parent_version:     StateVersion,  // For diff computation
    
    allocator:          mem.Allocator,
}

// StateSnapshot holds a complete serializable state
StateSnapshot :: struct {
    // Atom data (serialized form)
    atoms:              [dynamic]AtomRecord,
    
    // Attention values
    attention_values:   map[atom.Handle]atom.AttentionValue,
    
    // Truth values (only non-default)
    truth_values:       map[atom.Handle]atom.TruthValue,
    
    // Creation timestamp
    created_at:         time.Time,
    tick:               u64,
    
    allocator:          mem.Allocator,
}

// AtomRecord is a serializable atom representation
AtomRecord :: struct {
    handle:             atom.Handle,
    atom_type:          types.AtomType,
    truth_value:        atom.TruthValue,
    attention_value:    atom.AttentionValue,
    
    // Node or Link specific
    name:               string,           // For nodes
    outgoing:           []atom.Handle,    // For links
}

// AttentionSummary captures attention statistics
AttentionSummary :: struct {
    total_sti:          i64,
    total_lti:          i64,
    atoms_in_focus:     int,
    focus_boundary:     i16,
    top_atoms:          [10]atom.Handle,
    top_sti:            [10]i16,
}

// InferenceSnapshot captures inference engine state
InferenceSnapshot :: struct {
    active_rules:       int,
    pending_inferences: int,
    completed_cycles:   u64,
    free_energy:        f64,
    entropy:            f64,
}

// =============================================================================
// TRANSACTION LOG
// =============================================================================

// TransactionType indicates what kind of mutation occurred
TransactionType :: enum {
    ADD_NODE,
    ADD_LINK,
    REMOVE_ATOM,
    UPDATE_TV,
    UPDATE_AV,
    BATCH,
}

// Transaction records a single state mutation
Transaction :: struct {
    id:             TransactionID,
    type:           TransactionType,
    timestamp:      time.Time,
    tick:           u64,
    
    // Mutation data
    handle:         atom.Handle,
    
    // For ADD operations
    atom_type:      types.AtomType,
    name:           string,
    outgoing:       []atom.Handle,
    
    // For UPDATE operations
    old_tv:         atom.TruthValue,
    new_tv:         atom.TruthValue,
    old_av:         atom.AttentionValue,
    new_av:         atom.AttentionValue,
    
    // For BATCH operations
    sub_transactions: []Transaction,
}

// =============================================================================
// STATE DIFF
// =============================================================================

// StateDiff represents the difference between two states
StateDiff :: struct {
    from_version:       StateVersion,
    to_version:         StateVersion,
    
    // Changes
    added_atoms:        [dynamic]atom.Handle,
    removed_atoms:      [dynamic]atom.Handle,
    modified_atoms:     [dynamic]atom.Handle,
    
    // TV/AV changes
    tv_changes:         map[atom.Handle]TruthValueChange,
    av_changes:         map[atom.Handle]AttentionValueChange,
    
    // Aggregate metrics
    total_changes:      int,
    
    allocator:          mem.Allocator,
}

TruthValueChange :: struct {
    old_value:  atom.TruthValue,
    new_value:  atom.TruthValue,
}

AttentionValueChange :: struct {
    old_value:  atom.AttentionValue,
    new_value:  atom.AttentionValue,
}

// =============================================================================
// WORLD STATE LIFECYCLE
// =============================================================================

// Create a new world state
world_state_create :: proc(
    as: ^atomspace.AtomSpace,
    allocator := context.allocator,
) -> ^WorldState {
    ws := new(WorldState, allocator)
    
    ws.version = 1
    ws.timestamp = time.now()
    ws.tick = 0
    ws.atomspace = as
    ws.transactions = make([dynamic]Transaction, allocator)
    ws.parent_version = 0
    ws.allocator = allocator
    
    // Initialize attention summary
    world_state_update_attention_summary(ws)
    
    return ws
}

// Destroy a world state
world_state_destroy :: proc(ws: ^WorldState) {
    if ws == nil {
        return
    }
    
    // Free snapshot if exists
    if ws.snapshot != nil {
        snapshot_destroy(ws.snapshot)
    }
    
    // Free transactions
    for &t in ws.transactions {
        transaction_destroy(&t, ws.allocator)
    }
    delete(ws.transactions)
    
    free(ws, ws.allocator)
}

// =============================================================================
// STATE OPERATIONS
// =============================================================================

// Increment state version
world_state_next_version :: proc(ws: ^WorldState) -> StateVersion {
    ws.parent_version = ws.version
    ws.version += 1
    ws.timestamp = time.now()
    return ws.version
}

// Advance tick
world_state_advance_tick :: proc(ws: ^WorldState) {
    ws.tick += 1
    world_state_next_version(ws)
}

// Update attention summary from atomspace
world_state_update_attention_summary :: proc(ws: ^WorldState) {
    summary := &ws.attention_summary
    summary.total_sti = 0
    summary.total_lti = 0
    summary.atoms_in_focus = 0
    
    // Clear top atoms
    for i := 0; i < 10; i += 1 {
        summary.top_atoms[i] = atom.INVALID_HANDLE
        summary.top_sti[i] = min(i16)
    }
    
    // Iterate through atomspace
    it := atomspace.atomspace_iterator(ws.atomspace)
    for {
        a, h, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        av := a.attention_value
        summary.total_sti += i64(av.sti)
        summary.total_lti += i64(av.lti)
        
        if av.sti >= atom.ATTENTIONAL_FOCUS_BOUNDARY {
            summary.atoms_in_focus += 1
        }
        
        // Track top 10 by STI
        for i := 0; i < 10; i += 1 {
            if av.sti > summary.top_sti[i] {
                // Shift down
                for j := 9; j > i; j -= 1 {
                    summary.top_atoms[j] = summary.top_atoms[j-1]
                    summary.top_sti[j] = summary.top_sti[j-1]
                }
                summary.top_atoms[i] = h
                summary.top_sti[i] = av.sti
                break
            }
        }
    }
}

// =============================================================================
// TRANSACTION LOGGING
// =============================================================================

next_transaction_id: TransactionID = 0

// Log an add node transaction
world_state_log_add_node :: proc(
    ws: ^WorldState,
    handle: atom.Handle,
    atom_type: types.AtomType,
    name: string,
    tv: atom.TruthValue,
    av: atom.AttentionValue,
) {
    next_transaction_id += 1
    
    t := Transaction{
        id = next_transaction_id,
        type = .ADD_NODE,
        timestamp = time.now(),
        tick = ws.tick,
        handle = handle,
        atom_type = atom_type,
        name = name,
        new_tv = tv,
        new_av = av,
    }
    
    append(&ws.transactions, t)
    world_state_next_version(ws)
}

// Log an add link transaction
world_state_log_add_link :: proc(
    ws: ^WorldState,
    handle: atom.Handle,
    atom_type: types.AtomType,
    outgoing: []atom.Handle,
    tv: atom.TruthValue,
    av: atom.AttentionValue,
) {
    next_transaction_id += 1
    
    t := Transaction{
        id = next_transaction_id,
        type = .ADD_LINK,
        timestamp = time.now(),
        tick = ws.tick,
        handle = handle,
        atom_type = atom_type,
        outgoing = slice.clone(outgoing, ws.allocator),
        new_tv = tv,
        new_av = av,
    }
    
    append(&ws.transactions, t)
    world_state_next_version(ws)
}

// Log a remove atom transaction
world_state_log_remove :: proc(ws: ^WorldState, handle: atom.Handle) {
    next_transaction_id += 1
    
    t := Transaction{
        id = next_transaction_id,
        type = .REMOVE_ATOM,
        timestamp = time.now(),
        tick = ws.tick,
        handle = handle,
    }
    
    append(&ws.transactions, t)
    world_state_next_version(ws)
}

// Log a truth value update
world_state_log_tv_update :: proc(
    ws: ^WorldState,
    handle: atom.Handle,
    old_tv: atom.TruthValue,
    new_tv: atom.TruthValue,
) {
    next_transaction_id += 1
    
    t := Transaction{
        id = next_transaction_id,
        type = .UPDATE_TV,
        timestamp = time.now(),
        tick = ws.tick,
        handle = handle,
        old_tv = old_tv,
        new_tv = new_tv,
    }
    
    append(&ws.transactions, t)
    world_state_next_version(ws)
}

// Log an attention value update
world_state_log_av_update :: proc(
    ws: ^WorldState,
    handle: atom.Handle,
    old_av: atom.AttentionValue,
    new_av: atom.AttentionValue,
) {
    next_transaction_id += 1
    
    t := Transaction{
        id = next_transaction_id,
        type = .UPDATE_AV,
        timestamp = time.now(),
        tick = ws.tick,
        handle = handle,
        old_av = old_av,
        new_av = new_av,
    }
    
    append(&ws.transactions, t)
    world_state_next_version(ws)
}

// Clear transaction log
world_state_clear_transactions :: proc(ws: ^WorldState) {
    for &t in ws.transactions {
        transaction_destroy(&t, ws.allocator)
    }
    clear(&ws.transactions)
}

// Free transaction resources
transaction_destroy :: proc(t: ^Transaction, allocator: mem.Allocator) {
    if t.outgoing != nil {
        delete(t.outgoing, allocator)
    }
    if t.sub_transactions != nil {
        delete(t.sub_transactions, allocator)
    }
}

// =============================================================================
// SNAPSHOT OPERATIONS
// =============================================================================

// Create a snapshot of the current state
world_state_snapshot :: proc(ws: ^WorldState) -> ^StateSnapshot {
    snap := new(StateSnapshot, ws.allocator)
    snap.atoms = make([dynamic]AtomRecord, ws.allocator)
    snap.attention_values = make(map[atom.Handle]atom.AttentionValue, ws.allocator)
    snap.truth_values = make(map[atom.Handle]atom.TruthValue, ws.allocator)
    snap.created_at = time.now()
    snap.tick = ws.tick
    snap.allocator = ws.allocator
    
    // Serialize all atoms
    it := atomspace.atomspace_iterator(ws.atomspace)
    for {
        a, h, ok := atomspace.atomspace_iterate(&it)
        if !ok {
            break
        }
        
        record := AtomRecord{
            handle = h,
            atom_type = a.atom_type,
            truth_value = a.truth_value,
            attention_value = a.attention_value,
        }
        
        if atom.atom_is_node(a) {
            record.name = a.data.node.name
        } else if atom.atom_is_link(a) {
            record.outgoing = slice.clone(a.data.link.outgoing[:], ws.allocator)
        }
        
        append(&snap.atoms, record)
        
        // Store non-default values
        if !atom.tv_is_default(a.truth_value) {
            snap.truth_values[h] = a.truth_value
        }
        if a.attention_value != atom.DEFAULT_AV {
            snap.attention_values[h] = a.attention_value
        }
    }
    
    ws.snapshot = snap
    return snap
}

// Destroy a snapshot
snapshot_destroy :: proc(snap: ^StateSnapshot) {
    if snap == nil {
        return
    }
    
    for &record in snap.atoms {
        if record.outgoing != nil {
            delete(record.outgoing, snap.allocator)
        }
    }
    delete(snap.atoms)
    delete(snap.attention_values)
    delete(snap.truth_values)
    free(snap, snap.allocator)
}

// =============================================================================
// STATE DIFF
// =============================================================================

// Compute diff between two states
world_state_diff :: proc(
    from: ^WorldState,
    to: ^WorldState,
    allocator := context.allocator,
) -> ^StateDiff {
    diff := new(StateDiff, allocator)
    diff.from_version = from.version
    diff.to_version = to.version
    diff.added_atoms = make([dynamic]atom.Handle, allocator)
    diff.removed_atoms = make([dynamic]atom.Handle, allocator)
    diff.modified_atoms = make([dynamic]atom.Handle, allocator)
    diff.tv_changes = make(map[atom.Handle]TruthValueChange, allocator)
    diff.av_changes = make(map[atom.Handle]AttentionValueChange, allocator)
    diff.allocator = allocator
    
    // Build handle sets for comparison
    from_handles := make(map[atom.Handle]bool, context.temp_allocator)
    to_handles := make(map[atom.Handle]bool, context.temp_allocator)
    
    it := atomspace.atomspace_iterator(from.atomspace)
    for {
        _, h, ok := atomspace.atomspace_iterate(&it)
        if !ok { break }
        from_handles[h] = true
    }
    
    it = atomspace.atomspace_iterator(to.atomspace)
    for {
        _, h, ok := atomspace.atomspace_iterate(&it)
        if !ok { break }
        to_handles[h] = true
    }
    
    // Find added atoms
    for h in to_handles {
        if !(h in from_handles) {
            append(&diff.added_atoms, h)
        }
    }
    
    // Find removed atoms
    for h in from_handles {
        if !(h in to_handles) {
            append(&diff.removed_atoms, h)
        }
    }
    
    // Find modified atoms
    for h in to_handles {
        if h in from_handles {
            from_atom, _ := atomspace.atomspace_get(from.atomspace, h)
            to_atom, _ := atomspace.atomspace_get(to.atomspace, h)
            
            tv_changed := from_atom.truth_value != to_atom.truth_value
            av_changed := from_atom.attention_value != to_atom.attention_value
            
            if tv_changed || av_changed {
                append(&diff.modified_atoms, h)
                
                if tv_changed {
                    diff.tv_changes[h] = TruthValueChange{
                        old_value = from_atom.truth_value,
                        new_value = to_atom.truth_value,
                    }
                }
                
                if av_changed {
                    diff.av_changes[h] = AttentionValueChange{
                        old_value = from_atom.attention_value,
                        new_value = to_atom.attention_value,
                    }
                }
            }
        }
    }
    
    diff.total_changes = len(diff.added_atoms) + len(diff.removed_atoms) + len(diff.modified_atoms)
    
    return diff
}

// Destroy a state diff
state_diff_destroy :: proc(diff: ^StateDiff) {
    if diff == nil {
        return
    }
    
    delete(diff.added_atoms)
    delete(diff.removed_atoms)
    delete(diff.modified_atoms)
    delete(diff.tv_changes)
    delete(diff.av_changes)
    free(diff, diff.allocator)
}

// =============================================================================
// CHECKPOINTING
// =============================================================================

// Checkpoint is a serializable state at a point in time
Checkpoint :: struct {
    version:        StateVersion,
    tick:           u64,
    timestamp:      time.Time,
    snapshot:       ^StateSnapshot,
    checksum:       StateChecksum,
}

// Create a checkpoint
world_state_checkpoint :: proc(ws: ^WorldState) -> ^Checkpoint {
    cp := new(Checkpoint, ws.allocator)
    cp.version = ws.version
    cp.tick = ws.tick
    cp.timestamp = time.now()
    cp.snapshot = world_state_snapshot(ws)
    cp.checksum = world_state_compute_checksum(ws)
    return cp
}

// Destroy a checkpoint
checkpoint_destroy :: proc(cp: ^Checkpoint, allocator: mem.Allocator) {
    if cp == nil {
        return
    }
    snapshot_destroy(cp.snapshot)
    free(cp, allocator)
}

// Compute checksum of world state
world_state_compute_checksum :: proc(ws: ^WorldState) -> StateChecksum {
    // Simple checksum based on atom count and version
    checksum: StateChecksum = 0
    checksum ^= StateChecksum(ws.version)
    checksum ^= StateChecksum(ws.tick) << 8
    checksum ^= StateChecksum(atomspace.atomspace_size(ws.atomspace)) << 16
    return checksum
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Get current state version
world_state_version :: proc(ws: ^WorldState) -> StateVersion {
    return ws.version
}

// Get current tick
world_state_tick :: proc(ws: ^WorldState) -> u64 {
    return ws.tick
}

// Get transaction count since last snapshot
world_state_transaction_count :: proc(ws: ^WorldState) -> int {
    return len(ws.transactions)
}

// Get attention summary
world_state_attention_summary :: proc(ws: ^WorldState) -> AttentionSummary {
    return ws.attention_summary
}

// Get inference state
world_state_inference_state :: proc(ws: ^WorldState) -> InferenceSnapshot {
    return ws.inference_state
}

// Update inference state
world_state_set_inference_state :: proc(ws: ^WorldState, state: InferenceSnapshot) {
    ws.inference_state = state
    world_state_next_version(ws)
}

// Format state as string
world_state_to_string :: proc(ws: ^WorldState, allocator := context.allocator) -> string {
    return fmt.aprintf(
        "WorldState v%d (tick %d)\n" +
        "  Atoms: %d\n" +
        "  Total STI: %d, In Focus: %d\n" +
        "  Transactions: %d\n" +
        "  Free Energy: %.4f",
        ws.version, ws.tick,
        atomspace.atomspace_size(ws.atomspace),
        ws.attention_summary.total_sti, ws.attention_summary.atoms_in_focus,
        len(ws.transactions),
        ws.inference_state.free_energy,
        allocator = allocator,
    )
}
