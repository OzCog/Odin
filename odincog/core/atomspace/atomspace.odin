// OdinCog - OpenCog Implementation in Pure Odin
// AtomSpace - Central Hypergraph Knowledge Container
//
// The AtomSpace is the central knowledge store in OpenCog.
// It provides:
// - Storage for atoms (nodes and links)
// - O(1) handle-based lookup
// - Type-based indexing
// - Name-based indexing for nodes
// - Incoming set tracking
// - Thread-safe concurrent access

package odincog_atomspace

import "core:sync"
import "core:mem"
import "core:strings"
import "core:fmt"
import "../atom"
import "../types"

// =============================================================================
// ATOMSPACE STRUCTURE
// =============================================================================

// AtomSpace is the central hypergraph container
AtomSpace :: struct {
    // Primary storage
    atoms:       [dynamic]atom.Atom,      // Atom storage array
    free_list:   [dynamic]u32,            // Recycled indices
    generations: [dynamic]u32,            // Generation counter per slot
    
    // Indices for efficient lookup
    type_index:  map[types.AtomType][dynamic]atom.Handle,  // Type -> handles
    name_index:  map[string]atom.Handle,                    // Name -> handle (nodes)
    
    // Incoming set tracking: which links point to each atom
    incoming_index: map[u32][dynamic]atom.Handle,           // Target idx -> link handles
    
    // Concurrency control
    rw_lock: sync.RW_Mutex,
    
    // Statistics
    stats: AtomSpaceStats,
    
    // Memory management
    allocator: mem.Allocator,
    
    // Optional parent atomspace for hierarchical lookup
    parent: ^AtomSpace,
    
    // Name for identification
    name: string,
}

// AtomSpace statistics
AtomSpaceStats :: struct {
    total_atoms:    u64,
    total_nodes:    u64,
    total_links:    u64,
    max_atoms:      u64,
    lookups:        u64,
    cache_hits:     u64,
}

// =============================================================================
// ATOMSPACE LIFECYCLE
// =============================================================================

// Create a new AtomSpace
atomspace_create :: proc(
    name: string = "main",
    parent: ^AtomSpace = nil,
    allocator := context.allocator,
) -> ^AtomSpace {
    as := new(AtomSpace, allocator)
    
    as.atoms = make([dynamic]atom.Atom, allocator)
    as.free_list = make([dynamic]u32, allocator)
    as.generations = make([dynamic]u32, allocator)
    as.type_index = make(map[types.AtomType][dynamic]atom.Handle, 64, allocator)
    as.name_index = make(map[string]atom.Handle, allocator)
    as.incoming_index = make(map[u32][dynamic]atom.Handle, allocator)
    as.allocator = allocator
    as.parent = parent
    as.name = strings.clone(name, allocator)
    
    // Reserve index 0 as invalid sentinel
    append(&as.atoms, atom.Atom{})
    append(&as.generations, 0)
    
    return as
}

// Destroy an AtomSpace and free all resources
atomspace_destroy :: proc(as: ^AtomSpace) {
    if as == nil {
        return
    }
    
    // Free all atoms
    for i := 1; i < len(as.atoms); i += 1 {
        a := &as.atoms[i]
        if a.handle.idx != 0 {
            atom.atom_destroy(a, as.allocator)
        }
    }
    
    // Free indices
    for _, handles in as.type_index {
        delete(handles)
    }
    delete(as.type_index)
    delete(as.name_index)
    
    for _, handles in as.incoming_index {
        delete(handles)
    }
    delete(as.incoming_index)
    
    // Free primary storage
    delete(as.atoms)
    delete(as.free_list)
    delete(as.generations)
    delete(as.name, as.allocator)
    
    free(as, as.allocator)
}

// =============================================================================
// ATOM ADDITION
// =============================================================================

// Add a node to the AtomSpace
// Returns existing handle if node with same type+name already exists
add_node :: proc(
    as: ^AtomSpace,
    atom_type: types.AtomType,
    name: string,
    tv: atom.TruthValue = atom.DEFAULT_TV,
    av: atom.AttentionValue = atom.DEFAULT_AV,
) -> (atom.Handle, bool) {
    assert(types.is_node(atom_type), "add_node requires a node type")
    
    sync.shared_guard(&as.rw_lock)
    
    // Check for existing node with same type+name
    key := make_node_key(atom_type, name)
    if existing, ok := as.name_index[key]; ok {
        // Update truth value if provided is non-default
        if !atom.tv_is_default(tv) {
            if a, found := atomspace_get_unsafe(as, existing); found {
                a.truth_value = tv
            }
        }
        delete(key, as.allocator)
        return existing, false  // Existing atom
    }
    
    sync.shared_unlock(&as.rw_lock)
    sync.guard(&as.rw_lock)
    
    // Double-check after acquiring write lock
    if existing, ok := as.name_index[key]; ok {
        delete(key, as.allocator)
        return existing, false
    }
    
    // Create new node
    new_atom := atom.make_node(atom_type, name, tv, av, as.allocator)
    handle := allocate_handle(as)
    new_atom.handle = handle
    
    // Store atom
    if int(handle.idx) < len(as.atoms) {
        as.atoms[handle.idx] = new_atom
    } else {
        append(&as.atoms, new_atom)
    }
    
    // Update indices
    add_to_type_index(as, atom_type, handle)
    as.name_index[key] = handle
    
    // Update stats
    as.stats.total_atoms += 1
    as.stats.total_nodes += 1
    as.stats.max_atoms = max(as.stats.max_atoms, as.stats.total_atoms)
    
    return handle, true  // New atom
}

// Add a link to the AtomSpace
// Returns existing handle if link with same type+outgoing already exists
add_link :: proc(
    as: ^AtomSpace,
    atom_type: types.AtomType,
    outgoing: []atom.Handle,
    tv: atom.TruthValue = atom.DEFAULT_TV,
    av: atom.AttentionValue = atom.DEFAULT_AV,
) -> (atom.Handle, bool) {
    assert(types.is_link(atom_type), "add_link requires a link type")
    
    // Validate all outgoing handles
    for h in outgoing {
        if !atomspace_contains(as, h) {
            return atom.INVALID_HANDLE, false
        }
    }
    
    sync.guard(&as.rw_lock)
    
    // Check for existing link with same type+outgoing
    // For unordered links, we need to compare sets
    if existing := find_existing_link(as, atom_type, outgoing); atom.handle_is_valid(existing) {
        // Update truth value if provided is non-default
        if !atom.tv_is_default(tv) {
            if a, found := atomspace_get_unsafe(as, existing); found {
                a.truth_value = tv
            }
        }
        return existing, false  // Existing atom
    }
    
    // Create new link
    new_atom := atom.make_link(atom_type, outgoing, tv, av, as.allocator)
    handle := allocate_handle(as)
    new_atom.handle = handle
    
    // Store atom
    if int(handle.idx) < len(as.atoms) {
        as.atoms[handle.idx] = new_atom
    } else {
        append(&as.atoms, new_atom)
    }
    
    // Update indices
    add_to_type_index(as, atom_type, handle)
    
    // Update incoming sets
    for target in outgoing {
        add_to_incoming(as, target.idx, handle)
    }
    
    // Update stats
    as.stats.total_atoms += 1
    as.stats.total_links += 1
    as.stats.max_atoms = max(as.stats.max_atoms, as.stats.total_atoms)
    
    return handle, true  // New atom
}

// =============================================================================
// ATOM LOOKUP
// =============================================================================

// Get an atom by handle (thread-safe)
atomspace_get :: proc(as: ^AtomSpace, h: atom.Handle) -> (^atom.Atom, bool) {
    sync.shared_guard(&as.rw_lock)
    as.stats.lookups += 1
    return atomspace_get_unsafe(as, h)
}

// Get an atom by handle (not thread-safe, caller must hold lock)
atomspace_get_unsafe :: proc(as: ^AtomSpace, h: atom.Handle) -> (^atom.Atom, bool) {
    if h.idx == 0 || int(h.idx) >= len(as.atoms) {
        return nil, false
    }
    
    a := &as.atoms[h.idx]
    if a.handle.gen != h.gen {
        return nil, false  // Stale handle
    }
    
    return a, true
}

// Check if AtomSpace contains a handle
atomspace_contains :: proc(as: ^AtomSpace, h: atom.Handle) -> bool {
    _, found := atomspace_get(as, h)
    return found
}

// Get node by type and name
get_node :: proc(as: ^AtomSpace, atom_type: types.AtomType, name: string) -> (atom.Handle, bool) {
    sync.shared_guard(&as.rw_lock)
    
    key := make_node_key(atom_type, name)
    defer delete(key, as.allocator)
    
    if handle, ok := as.name_index[key]; ok {
        return handle, true
    }
    
    // Check parent if not found
    if as.parent != nil {
        return get_node(as.parent, atom_type, name)
    }
    
    return atom.INVALID_HANDLE, false
}

// Get all atoms of a specific type
get_atoms_by_type :: proc(
    as: ^AtomSpace,
    atom_type: types.AtomType,
    include_subtypes: bool = true,
) -> []atom.Handle {
    sync.shared_guard(&as.rw_lock)
    
    result := make([dynamic]atom.Handle, as.allocator)
    
    if include_subtypes {
        // Include all subtypes
        for t, handles in as.type_index {
            if types.is_subtype_of(t, atom_type) {
                for h in handles {
                    append(&result, h)
                }
            }
        }
    } else {
        // Exact type only
        if handles, ok := as.type_index[atom_type]; ok {
            for h in handles {
                append(&result, h)
            }
        }
    }
    
    return result[:]
}

// Get incoming set (all links pointing to this atom)
get_incoming :: proc(as: ^AtomSpace, h: atom.Handle) -> []atom.Handle {
    sync.shared_guard(&as.rw_lock)
    
    if handles, ok := as.incoming_index[h.idx]; ok {
        return handles[:]
    }
    return nil
}

// Get incoming set filtered by type
get_incoming_by_type :: proc(
    as: ^AtomSpace,
    h: atom.Handle,
    link_type: types.AtomType,
) -> []atom.Handle {
    sync.shared_guard(&as.rw_lock)
    
    result := make([dynamic]atom.Handle, as.allocator)
    
    if handles, ok := as.incoming_index[h.idx]; ok {
        for link_h in handles {
            if link_atom, found := atomspace_get_unsafe(as, link_h); found {
                if types.is_subtype_of(link_atom.atom_type, link_type) {
                    append(&result, link_h)
                }
            }
        }
    }
    
    return result[:]
}

// =============================================================================
// ATOM REMOVAL
// =============================================================================

// Remove an atom from the AtomSpace
// Returns false if atom has incoming links (is target of other atoms)
remove_atom :: proc(as: ^AtomSpace, h: atom.Handle, recursive: bool = false) -> bool {
    sync.guard(&as.rw_lock)
    
    a, found := atomspace_get_unsafe(as, h)
    if !found {
        return false
    }
    
    // Check for incoming links
    if incoming, ok := as.incoming_index[h.idx]; ok && len(incoming) > 0 {
        if recursive {
            // Remove all links pointing to this atom first
            for link_h in incoming {
                remove_atom_internal(as, link_h)
            }
        } else {
            return false  // Cannot remove atom with incoming links
        }
    }
    
    return remove_atom_internal(as, h)
}

// Internal removal (assumes write lock held)
remove_atom_internal :: proc(as: ^AtomSpace, h: atom.Handle) -> bool {
    a, found := atomspace_get_unsafe(as, h)
    if !found {
        return false
    }
    
    // Remove from type index
    if handles, ok := as.type_index[a.atom_type]; ok {
        for i := 0; i < len(handles); i += 1 {
            if atom.handle_equals(handles[i], h) {
                unordered_remove(&handles, i)
                break
            }
        }
    }
    
    // Remove from name index (if node)
    if atom.atom_is_node(a) {
        key := make_node_key(a.atom_type, a.data.node.name)
        delete_key(&as.name_index, key)
        delete(key, as.allocator)
    }
    
    // Remove from incoming sets (if link)
    if atom.atom_is_link(a) {
        for target in a.data.link.outgoing {
            remove_from_incoming(as, target.idx, h)
        }
    }
    
    // Remove from incoming index (this atom as target)
    delete_key(&as.incoming_index, h.idx)
    
    // Free atom resources
    atom.atom_destroy(a, as.allocator)
    
    // Mark slot as free
    a.handle = atom.INVALID_HANDLE
    as.generations[h.idx] += 1
    append(&as.free_list, h.idx)
    
    // Update stats
    as.stats.total_atoms -= 1
    if atom.atom_is_node(a) {
        as.stats.total_nodes -= 1
    } else {
        as.stats.total_links -= 1
    }
    
    return true
}

// =============================================================================
// ATOMSPACE QUERIES
// =============================================================================

// Get total atom count
atomspace_size :: proc(as: ^AtomSpace) -> u64 {
    sync.shared_guard(&as.rw_lock)
    return as.stats.total_atoms
}

// Get node count
atomspace_node_count :: proc(as: ^AtomSpace) -> u64 {
    sync.shared_guard(&as.rw_lock)
    return as.stats.total_nodes
}

// Get link count
atomspace_link_count :: proc(as: ^AtomSpace) -> u64 {
    sync.shared_guard(&as.rw_lock)
    return as.stats.total_links
}

// Get statistics
atomspace_stats :: proc(as: ^AtomSpace) -> AtomSpaceStats {
    sync.shared_guard(&as.rw_lock)
    return as.stats
}

// Clear all atoms from the AtomSpace
atomspace_clear :: proc(as: ^AtomSpace) {
    sync.guard(&as.rw_lock)
    
    // Free all atoms
    for i := 1; i < len(as.atoms); i += 1 {
        a := &as.atoms[i]
        if a.handle.idx != 0 {
            atom.atom_destroy(a, as.allocator)
        }
    }
    
    // Clear storage
    clear(&as.atoms)
    clear(&as.free_list)
    clear(&as.generations)
    
    // Clear indices
    for _, handles in as.type_index {
        clear(&handles)
    }
    clear(&as.name_index)
    
    for _, handles in as.incoming_index {
        clear(&handles)
    }
    clear(&as.incoming_index)
    
    // Re-add sentinel
    append(&as.atoms, atom.Atom{})
    append(&as.generations, 0)
    
    // Reset stats
    as.stats = AtomSpaceStats{}
}

// =============================================================================
// ITERATION
// =============================================================================

// Iterator for all atoms in the AtomSpace
AtomSpaceIterator :: struct {
    as:    ^AtomSpace,
    index: int,
}

// Create iterator
atomspace_iterator :: proc(as: ^AtomSpace) -> AtomSpaceIterator {
    return AtomSpaceIterator{as = as, index = 1}
}

// Iterate to next atom
atomspace_iterate :: proc(it: ^AtomSpaceIterator) -> (^atom.Atom, atom.Handle, bool) {
    for it.index < len(it.as.atoms) {
        a := &it.as.atoms[it.index]
        it.index += 1
        
        if a.handle.idx != 0 {
            return a, a.handle, true
        }
    }
    return nil, atom.INVALID_HANDLE, false
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// Allocate a new handle (reuse from free list or append)
allocate_handle :: proc(as: ^AtomSpace) -> atom.Handle {
    if len(as.free_list) > 0 {
        idx := pop(&as.free_list)
        gen := as.generations[idx] + 1
        as.generations[idx] = gen
        return atom.Handle{idx = idx, gen = gen}
    }
    
    idx := u32(len(as.atoms))
    append(&as.generations, 1)
    return atom.Handle{idx = idx, gen = 1}
}

// Make composite key for node lookup
make_node_key :: proc(atom_type: types.AtomType, name: string) -> string {
    return strings.concatenate({types.type_name(atom_type), ":", name})
}

// Add handle to type index
add_to_type_index :: proc(as: ^AtomSpace, atom_type: types.AtomType, h: atom.Handle) {
    if handles, ok := as.type_index[atom_type]; ok {
        append(&handles, h)
        as.type_index[atom_type] = handles
    } else {
        handles := make([dynamic]atom.Handle, as.allocator)
        append(&handles, h)
        as.type_index[atom_type] = handles
    }
}

// Add to incoming set
add_to_incoming :: proc(as: ^AtomSpace, target_idx: u32, link_h: atom.Handle) {
    if handles, ok := as.incoming_index[target_idx]; ok {
        append(&handles, link_h)
        as.incoming_index[target_idx] = handles
    } else {
        handles := make([dynamic]atom.Handle, as.allocator)
        append(&handles, link_h)
        as.incoming_index[target_idx] = handles
    }
}

// Remove from incoming set
remove_from_incoming :: proc(as: ^AtomSpace, target_idx: u32, link_h: atom.Handle) {
    if handles, ok := as.incoming_index[target_idx]; ok {
        for i := 0; i < len(handles); i += 1 {
            if atom.handle_equals(handles[i], link_h) {
                unordered_remove(&handles, i)
                as.incoming_index[target_idx] = handles
                return
            }
        }
    }
}

// Find existing link with same type and outgoing set
find_existing_link :: proc(
    as: ^AtomSpace,
    atom_type: types.AtomType,
    outgoing: []atom.Handle,
) -> atom.Handle {
    // Get all links of this type
    if handles, ok := as.type_index[atom_type]; ok {
        is_unordered := types.is_unordered_link(atom_type)
        
        for h in handles {
            if a, found := atomspace_get_unsafe(as, h); found {
                existing := atom.atom_get_outgoing(a)
                if len(existing) == len(outgoing) {
                    if is_unordered {
                        if outgoing_sets_equal_unordered(existing, outgoing) {
                            return h
                        }
                    } else {
                        if outgoing_sets_equal_ordered(existing, outgoing) {
                            return h
                        }
                    }
                }
            }
        }
    }
    return atom.INVALID_HANDLE
}

// Compare two outgoing sets (ordered)
outgoing_sets_equal_ordered :: proc(a: []atom.Handle, b: []atom.Handle) -> bool {
    if len(a) != len(b) {
        return false
    }
    for i := 0; i < len(a); i += 1 {
        if !atom.handle_equals(a[i], b[i]) {
            return false
        }
    }
    return true
}

// Compare two outgoing sets (unordered, as sets)
outgoing_sets_equal_unordered :: proc(a: []atom.Handle, b: []atom.Handle) -> bool {
    if len(a) != len(b) {
        return false
    }
    
    // Simple O(n²) comparison for small sets
    for ha in a {
        found := false
        for hb in b {
            if atom.handle_equals(ha, hb) {
                found = true
                break
            }
        }
        if !found {
            return false
        }
    }
    return true
}

// =============================================================================
// STRING REPRESENTATION
// =============================================================================

// Convert AtomSpace to string summary
atomspace_to_string :: proc(as: ^AtomSpace, allocator := context.allocator) -> string {
    builder := strings.builder_make(allocator)
    
    strings.write_string(&builder, fmt.tprintf("AtomSpace '%s': %d atoms (%d nodes, %d links)\n",
        as.name, as.stats.total_atoms, as.stats.total_nodes, as.stats.total_links))
    
    // List all atoms
    it := atomspace_iterator(as)
    for {
        a, h, ok := atomspace_iterate(&it)
        if !ok {
            break
        }
        strings.write_string(&builder, fmt.tprintf("  [%d] %s\n", h.idx, atom.atom_to_string(a)))
    }
    
    return strings.to_string(builder)
}
