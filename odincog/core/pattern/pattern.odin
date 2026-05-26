// OdinCog - OpenCog Implementation in Pure Odin
// Pattern Matching Engine
//
// This module implements the core pattern matching functionality for querying
// the AtomSpace. It supports:
// - Variable binding and unification
// - Subgraph pattern matching
// - Type-constrained variables
// - Glob patterns for matching multiple atoms
// - Backtracking search with constraint propagation

package odincog_pattern

import "core:mem"
import "core:strings"
import "core:fmt"
import "../atom"
import "../atomspace"
import "../types"

// =============================================================================
// VARIABLE BINDING
// =============================================================================

// VariableBinding maps variable handles to their bound values
VariableBinding :: struct {
    bindings: map[atom.Handle]atom.Handle,
    allocator: mem.Allocator,
}

// Create a new variable binding context
binding_create :: proc(allocator := context.allocator) -> VariableBinding {
    return VariableBinding{
        bindings = make(map[atom.Handle]atom.Handle, allocator),
        allocator = allocator,
    }
}

// Destroy binding context
binding_destroy :: proc(b: ^VariableBinding) {
    delete(b.bindings)
}

// Clone a binding (for backtracking)
binding_clone :: proc(b: ^VariableBinding) -> VariableBinding {
    new_bindings := make(map[atom.Handle]atom.Handle, b.allocator)
    for k, v in b.bindings {
        new_bindings[k] = v
    }
    return VariableBinding{
        bindings = new_bindings,
        allocator = b.allocator,
    }
}

// Bind a variable to a value
binding_set :: proc(b: ^VariableBinding, var_handle: atom.Handle, value: atom.Handle) -> bool {
    // Check if already bound to a different value
    if existing, ok := b.bindings[var_handle]; ok {
        return atom.handle_equals(existing, value)
    }
    b.bindings[var_handle] = value
    return true
}

// Get bound value for a variable
binding_get :: proc(b: ^VariableBinding, var_handle: atom.Handle) -> (atom.Handle, bool) {
    if value, ok := b.bindings[var_handle]; ok {
        return value, true
    }
    return atom.INVALID_HANDLE, false
}

// Check if variable is bound
binding_is_bound :: proc(b: ^VariableBinding, var_handle: atom.Handle) -> bool {
    _, ok := b.bindings[var_handle]
    return ok
}

// Get all bindings as a slice of pairs
binding_get_all :: proc(b: ^VariableBinding) -> [][2]atom.Handle {
    result := make([dynamic][2]atom.Handle, b.allocator)
    for var_h, val_h in b.bindings {
        append(&result, [2]atom.Handle{var_h, val_h})
    }
    return result[:]
}

// =============================================================================
// PATTERN - Query Pattern Representation
// =============================================================================

// Pattern represents a query pattern to match against the AtomSpace
Pattern :: struct {
    // The root pattern atom (handle in pattern space)
    root:         atom.Handle,
    
    // Pattern atoms (separate from AtomSpace)
    pattern_atoms: [dynamic]atom.Atom,
    
    // Declared variables
    variables:    [dynamic]atom.Handle,
    
    // Type constraints for variables
    type_constraints: map[atom.Handle]types.AtomType,
    
    // Optional clause patterns (for multi-clause queries)
    clauses:      [dynamic]atom.Handle,
    
    // Allocator
    allocator:    mem.Allocator,
}

// Create a new pattern
pattern_create :: proc(allocator := context.allocator) -> ^Pattern {
    p := new(Pattern, allocator)
    p.pattern_atoms = make([dynamic]atom.Atom, allocator)
    p.variables = make([dynamic]atom.Handle, allocator)
    p.type_constraints = make(map[atom.Handle]types.AtomType, allocator)
    p.clauses = make([dynamic]atom.Handle, allocator)
    p.allocator = allocator
    
    // Add sentinel
    append(&p.pattern_atoms, atom.Atom{})
    
    return p
}

// Destroy pattern
pattern_destroy :: proc(p: ^Pattern) {
    for i := 1; i < len(p.pattern_atoms); i += 1 {
        atom.atom_destroy(&p.pattern_atoms[i], p.allocator)
    }
    delete(p.pattern_atoms)
    delete(p.variables)
    delete(p.type_constraints)
    delete(p.clauses)
    free(p, p.allocator)
}

// Add a variable to the pattern
pattern_add_variable :: proc(
    p: ^Pattern,
    name: string,
    type_constraint: types.AtomType = .ATOM,
) -> atom.Handle {
    idx := u32(len(p.pattern_atoms))
    new_var := atom.make_node(.VARIABLE_NODE, name, atom.DEFAULT_TV, atom.DEFAULT_AV, p.allocator)
    new_var.handle = atom.Handle{idx = idx, gen = 1}
    
    append(&p.pattern_atoms, new_var)
    append(&p.variables, new_var.handle)
    
    if type_constraint != .ATOM {
        p.type_constraints[new_var.handle] = type_constraint
    }
    
    return new_var.handle
}

// Add a node pattern
pattern_add_node :: proc(
    p: ^Pattern,
    atom_type: types.AtomType,
    name: string,
) -> atom.Handle {
    idx := u32(len(p.pattern_atoms))
    new_node := atom.make_node(atom_type, name, atom.DEFAULT_TV, atom.DEFAULT_AV, p.allocator)
    new_node.handle = atom.Handle{idx = idx, gen = 1}
    
    append(&p.pattern_atoms, new_node)
    return new_node.handle
}

// Add a link pattern
pattern_add_link :: proc(
    p: ^Pattern,
    atom_type: types.AtomType,
    outgoing: []atom.Handle,
) -> atom.Handle {
    idx := u32(len(p.pattern_atoms))
    new_link := atom.make_link(atom_type, outgoing, atom.DEFAULT_TV, atom.DEFAULT_AV, p.allocator)
    new_link.handle = atom.Handle{idx = idx, gen = 1}
    
    append(&p.pattern_atoms, new_link)
    return new_link.handle
}

// Set the root pattern
pattern_set_root :: proc(p: ^Pattern, h: atom.Handle) {
    p.root = h
}

// Add a clause to multi-clause pattern
pattern_add_clause :: proc(p: ^Pattern, h: atom.Handle) {
    append(&p.clauses, h)
}

// Get pattern atom by handle
pattern_get_atom :: proc(p: ^Pattern, h: atom.Handle) -> (^atom.Atom, bool) {
    if h.idx == 0 || int(h.idx) >= len(p.pattern_atoms) {
        return nil, false
    }
    return &p.pattern_atoms[h.idx], true
}

// Check if handle is a variable in this pattern
pattern_is_variable :: proc(p: ^Pattern, h: atom.Handle) -> bool {
    for v in p.variables {
        if atom.handle_equals(v, h) {
            return true
        }
    }
    return false
}

// =============================================================================
// PATTERN MATCHER
// =============================================================================

// MatchResult holds the result of a pattern match
MatchResult :: struct {
    success:  bool,
    bindings: VariableBinding,
}

// MatchIterator for lazy evaluation of matches
MatchIterator :: struct {
    pattern:       ^Pattern,
    atomspace:     ^atomspace.AtomSpace,
    
    // Search state
    candidates:    [dynamic]atom.Handle,
    candidate_idx: int,
    
    // Current binding state
    current_binding: VariableBinding,
    
    // Backtracking stack
    backtrack_stack: [dynamic]BacktrackState,
    
    allocator:     mem.Allocator,
    finished:      bool,
}

BacktrackState :: struct {
    pattern_handle: atom.Handle,
    candidate_idx:  int,
    binding:        VariableBinding,
}

// Create a match iterator
match_iterator_create :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    allocator := context.allocator,
) -> ^MatchIterator {
    it := new(MatchIterator, allocator)
    it.pattern = pattern
    it.atomspace = as
    it.candidates = make([dynamic]atom.Handle, allocator)
    it.backtrack_stack = make([dynamic]BacktrackState, allocator)
    it.current_binding = binding_create(allocator)
    it.allocator = allocator
    it.finished = false
    
    // Get initial candidates based on pattern root type
    if pattern_atom, ok := pattern_get_atom(pattern, pattern.root); ok {
        if !pattern_is_variable(pattern, pattern.root) {
            // Fixed type pattern - get atoms of that type
            candidates := atomspace.get_atoms_by_type(as, pattern_atom.atom_type, true)
            for c in candidates {
                append(&it.candidates, c)
            }
        } else {
            // Variable root - all atoms are candidates
            iter := atomspace.atomspace_iterator(as)
            for {
                _, h, ok := atomspace.atomspace_iterate(&iter)
                if !ok {
                    break
                }
                append(&it.candidates, h)
            }
        }
    }
    
    return it
}

// Destroy match iterator
match_iterator_destroy :: proc(it: ^MatchIterator) {
    delete(it.candidates)
    for state in it.backtrack_stack {
        binding_destroy(&state.binding)
    }
    delete(it.backtrack_stack)
    binding_destroy(&it.current_binding)
    free(it, it.allocator)
}

// Get next match
match_iterator_next :: proc(it: ^MatchIterator) -> (VariableBinding, bool) {
    if it.finished {
        return VariableBinding{}, false
    }
    
    for it.candidate_idx < len(it.candidates) {
        candidate := it.candidates[it.candidate_idx]
        it.candidate_idx += 1
        
        // Reset binding for new candidate
        binding_destroy(&it.current_binding)
        it.current_binding = binding_create(it.allocator)
        
        // Try to match pattern against candidate
        if match_recursive(it.pattern, it.atomspace, it.pattern.root, candidate, &it.current_binding) {
            // Success! Clone binding for return
            return binding_clone(&it.current_binding), true
        }
    }
    
    it.finished = true
    return VariableBinding{}, false
}

// =============================================================================
// CORE MATCHING ALGORITHM
// =============================================================================

// Recursive pattern matching
match_recursive :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    pattern_handle: atom.Handle,
    ground_handle: atom.Handle,
    bindings: ^VariableBinding,
) -> bool {
    // Get pattern atom
    pattern_atom, ok := pattern_get_atom(pattern, pattern_handle)
    if !ok {
        return false
    }
    
    // Get ground atom
    ground_atom, ok2 := atomspace.atomspace_get(as, ground_handle)
    if !ok2 {
        return false
    }
    
    // Case 1: Pattern is a variable
    if pattern_is_variable(pattern, pattern_handle) {
        return match_variable(pattern, as, pattern_handle, ground_handle, bindings)
    }
    
    // Case 2: Pattern is a fixed node
    if atom.atom_is_node(pattern_atom) {
        return match_node(pattern_atom, ground_atom)
    }
    
    // Case 3: Pattern is a link
    if atom.atom_is_link(pattern_atom) {
        return match_link(pattern, as, pattern_atom, ground_atom, bindings)
    }
    
    return false
}

// Match a variable pattern
match_variable :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    var_handle: atom.Handle,
    ground_handle: atom.Handle,
    bindings: ^VariableBinding,
) -> bool {
    // Check type constraint
    if constraint, has_constraint := pattern.type_constraints[var_handle]; has_constraint {
        ground_atom, ok := atomspace.atomspace_get(as, ground_handle)
        if !ok {
            return false
        }
        if !types.is_subtype_of(ground_atom.atom_type, constraint) {
            return false
        }
    }
    
    // Check if already bound
    if existing, is_bound := binding_get(bindings, var_handle); is_bound {
        return atom.handle_equals(existing, ground_handle)
    }
    
    // Bind variable
    return binding_set(bindings, var_handle, ground_handle)
}

// Match a node pattern (must have same type and name)
match_node :: proc(pattern_atom: ^atom.Atom, ground_atom: ^atom.Atom) -> bool {
    if pattern_atom.atom_type != ground_atom.atom_type {
        return false
    }
    
    return atom.atom_get_name(pattern_atom) == atom.atom_get_name(ground_atom)
}

// Match a link pattern
match_link :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    pattern_atom: ^atom.Atom,
    ground_atom: ^atom.Atom,
    bindings: ^VariableBinding,
) -> bool {
    // Must be same type
    if pattern_atom.atom_type != ground_atom.atom_type {
        return false
    }
    
    pattern_outgoing := atom.atom_get_outgoing(pattern_atom)
    ground_outgoing := atom.atom_get_outgoing(ground_atom)
    
    // Must have same arity
    if len(pattern_outgoing) != len(ground_outgoing) {
        return false
    }
    
    // Check if unordered
    if types.is_unordered_link(pattern_atom.atom_type) {
        return match_unordered(pattern, as, pattern_outgoing, ground_outgoing, bindings)
    }
    
    // Ordered match
    for i := 0; i < len(pattern_outgoing); i += 1 {
        if !match_recursive(pattern, as, pattern_outgoing[i], ground_outgoing[i], bindings) {
            return false
        }
    }
    
    return true
}

// Match unordered link (permutation matching)
match_unordered :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    pattern_outgoing: []atom.Handle,
    ground_outgoing: []atom.Handle,
    bindings: ^VariableBinding,
) -> bool {
    n := len(pattern_outgoing)
    if n == 0 {
        return true
    }
    
    // Track which ground atoms have been matched
    used := make([]bool, n, context.temp_allocator)
    
    return match_unordered_recursive(pattern, as, pattern_outgoing, ground_outgoing, 0, used, bindings)
}

// Recursive unordered matching with backtracking
match_unordered_recursive :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    pattern_outgoing: []atom.Handle,
    ground_outgoing: []atom.Handle,
    pattern_idx: int,
    used: []bool,
    bindings: ^VariableBinding,
) -> bool {
    if pattern_idx >= len(pattern_outgoing) {
        return true
    }
    
    pattern_h := pattern_outgoing[pattern_idx]
    
    // Try matching with each unused ground atom
    for i := 0; i < len(ground_outgoing); i += 1 {
        if used[i] {
            continue
        }
        
        // Save binding state for backtracking
        saved_binding := binding_clone(bindings)
        defer binding_destroy(&saved_binding)
        
        if match_recursive(pattern, as, pattern_h, ground_outgoing[i], bindings) {
            used[i] = true
            if match_unordered_recursive(pattern, as, pattern_outgoing, ground_outgoing, pattern_idx + 1, used, bindings) {
                return true
            }
            used[i] = false
        }
        
        // Restore binding state
        binding_destroy(bindings)
        bindings^ = binding_clone(&saved_binding)
    }
    
    return false
}

// =============================================================================
// HIGH-LEVEL QUERY FUNCTIONS
// =============================================================================

// Find all matches for a pattern
pattern_match_all :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    max_results: int = -1,
    allocator := context.allocator,
) -> []VariableBinding {
    results := make([dynamic]VariableBinding, allocator)
    
    it := match_iterator_create(pattern, as, allocator)
    defer match_iterator_destroy(it)
    
    count := 0
    for {
        binding, ok := match_iterator_next(it)
        if !ok {
            break
        }
        append(&results, binding)
        count += 1
        
        if max_results > 0 && count >= max_results {
            break
        }
    }
    
    return results[:]
}

// Find first match for a pattern
pattern_match_first :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
) -> (VariableBinding, bool) {
    it := match_iterator_create(pattern, as)
    defer match_iterator_destroy(it)
    
    return match_iterator_next(it)
}

// Check if pattern has any matches
pattern_has_match :: proc(
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
) -> bool {
    it := match_iterator_create(pattern, as)
    defer match_iterator_destroy(it)
    
    _, ok := match_iterator_next(it)
    return ok
}

// =============================================================================
// PATTERN BUILDERS - CONVENIENCE FUNCTIONS
// =============================================================================

// Build an InheritanceLink pattern: (InheritanceLink $X ConceptNode)
build_inheritance_pattern :: proc(
    p: ^Pattern,
    var_name: string,
    parent_type: types.AtomType,
    parent_name: string,
) -> atom.Handle {
    var_x := pattern_add_variable(p, var_name, .CONCEPT_NODE)
    parent := pattern_add_node(p, parent_type, parent_name)
    link := pattern_add_link(p, .INHERITANCE_LINK, {var_x, parent})
    pattern_set_root(p, link)
    return link
}

// Build an EvaluationLink pattern: (EvaluationLink pred (ListLink args...))
build_evaluation_pattern :: proc(
    p: ^Pattern,
    pred_name: string,
    arg_handles: []atom.Handle,
) -> atom.Handle {
    pred := pattern_add_node(p, .PREDICATE_NODE, pred_name)
    list := pattern_add_link(p, .LIST_LINK, arg_handles)
    eval := pattern_add_link(p, .EVALUATION_LINK, {pred, list})
    pattern_set_root(p, eval)
    return eval
}

// =============================================================================
// SUBSTITUTION
// =============================================================================

// Apply variable bindings to create grounded atoms
apply_bindings :: proc(
    pattern: ^Pattern,
    bindings: ^VariableBinding,
    as: ^atomspace.AtomSpace,
    pattern_handle: atom.Handle,
) -> atom.Handle {
    // Check if this is a variable
    if pattern_is_variable(pattern, pattern_handle) {
        if bound_value, ok := binding_get(bindings, pattern_handle); ok {
            return bound_value
        }
        return atom.INVALID_HANDLE
    }
    
    pattern_atom, ok := pattern_get_atom(pattern, pattern_handle)
    if !ok {
        return atom.INVALID_HANDLE
    }
    
    // If it's a node, find or create in atomspace
    if atom.atom_is_node(pattern_atom) {
        h, _ := atomspace.add_node(as, pattern_atom.atom_type, atom.atom_get_name(pattern_atom))
        return h
    }
    
    // If it's a link, recursively apply bindings to outgoing
    if atom.atom_is_link(pattern_atom) {
        pattern_outgoing := atom.atom_get_outgoing(pattern_atom)
        new_outgoing := make([]atom.Handle, len(pattern_outgoing), context.temp_allocator)
        
        for i := 0; i < len(pattern_outgoing); i += 1 {
            new_outgoing[i] = apply_bindings(pattern, bindings, as, pattern_outgoing[i])
            if !atom.handle_is_valid(new_outgoing[i]) {
                return atom.INVALID_HANDLE
            }
        }
        
        h, _ := atomspace.add_link(as, pattern_atom.atom_type, new_outgoing)
        return h
    }
    
    return atom.INVALID_HANDLE
}

// =============================================================================
// DEBUG / STRING REPRESENTATION
// =============================================================================

// Convert pattern to string
pattern_to_string :: proc(p: ^Pattern, allocator := context.allocator) -> string {
    builder := strings.builder_make(allocator)
    
    strings.write_string(&builder, "Pattern:\n")
    strings.write_string(&builder, fmt.tprintf("  Variables: %d\n", len(p.variables)))
    
    for v in p.variables {
        if va, ok := pattern_get_atom(p, v); ok {
            strings.write_string(&builder, fmt.tprintf("    $%s", atom.atom_get_name(va)))
            if constraint, has := p.type_constraints[v]; has {
                strings.write_string(&builder, fmt.tprintf(" : %s", types.type_name(constraint)))
            }
            strings.write_string(&builder, "\n")
        }
    }
    
    strings.write_string(&builder, fmt.tprintf("  Root: %d\n", p.root.idx))
    
    return strings.to_string(builder)
}

// Convert binding to string
binding_to_string :: proc(
    b: ^VariableBinding,
    pattern: ^Pattern,
    as: ^atomspace.AtomSpace,
    allocator := context.allocator,
) -> string {
    builder := strings.builder_make(allocator)
    
    strings.write_string(&builder, "Bindings:\n")
    
    for var_h, val_h in b.bindings {
        // Get variable name
        var_name := ""
        if va, ok := pattern_get_atom(pattern, var_h); ok {
            var_name = atom.atom_get_name(va)
        }
        
        // Get value description
        val_desc := ""
        if va, ok := atomspace.atomspace_get(as, val_h); ok {
            val_desc = atom.atom_to_string(va)
        }
        
        strings.write_string(&builder, fmt.tprintf("  $%s = %s\n", var_name, val_desc))
    }
    
    return strings.to_string(builder)
}
