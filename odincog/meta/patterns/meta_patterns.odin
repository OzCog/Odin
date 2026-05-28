// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Meta-Patterns
//
// This module implements meta-patterns - patterns that match over
// code structure rather than just data. This enables the agent to
// reason about its own code and identify patterns like:
// - "All procedures that modify AtomSpace"
// - "All rules that produce InheritanceLinks"

package odincog_meta_patterns

import "core:mem"
import "core:strings"
import "../types"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/pattern"
import coreTypes "../../core/types"

// =============================================================================
// META-PATTERN TYPES
// =============================================================================

// MetaPatternType indicates what kind of code pattern to match
MetaPatternType :: enum {
    // Structural patterns
    PROCEDURE_MATCHING,         // Match procedures by properties
    TYPE_MATCHING,              // Match types by properties
    MODULE_MATCHING,            // Match modules by properties
    
    // Relationship patterns
    CALL_PATTERN,               // Match call relationships
    DEPENDENCY_PATTERN,         // Match import/dependency relationships
    DATA_FLOW_PATTERN,          // Match data flow through code
    
    // Behavioral patterns
    MODIFICATION_PATTERN,       // Procedures that modify state
    PURE_FUNCTION_PATTERN,      // Pure functions (no side effects)
    RECURSIVE_PATTERN,          // Recursive procedures
    
    // Rule patterns
    RULE_PRODUCES_PATTERN,      // Rules that produce certain atom types
    RULE_MATCHES_PATTERN,       // Rules that match certain patterns
}

// MetaPattern represents a pattern over code structure
MetaPattern :: struct {
    name:               string,
    type:               MetaPatternType,
    
    // Matching criteria
    criteria:           MetaPatternCriteria,
    
    // Optional custom matcher
    custom_matcher:     proc(^MetaPattern, atom.Handle, ^atomspace.AtomSpace) -> bool,
    
    // Results
    matches:            [dynamic]MetaPatternMatch,
    
    // Statistics
    times_matched:      int,
    total_matches:      int,
    
    allocator:          mem.Allocator,
}

// MetaPatternCriteria defines matching rules
MetaPatternCriteria :: struct {
    // Type constraints
    target_types:       []types.CodeAtomType,
    
    // Name constraints
    name_contains:      string,
    name_prefix:        string,
    name_suffix:        string,
    name_regex:         string,
    
    // Structural constraints
    min_calls:          int,
    max_calls:          int,
    min_parameters:     int,
    max_parameters:     int,
    
    // Relationship constraints
    must_call:          []string,           // Must call these procedures
    must_not_call:      []string,           // Must not call these
    must_read:          []string,           // Must read these variables
    must_write:         []string,           // Must write these variables
    
    // Property constraints
    must_be_public:     bool,
    must_be_pure:       bool,
    must_be_recursive:  bool,
    
    // Output constraints (for rules)
    produces_type:      []coreTypes.AtomType,
    matches_pattern:    ^pattern.Pattern,
}

// MetaPatternMatch represents a single match
MetaPatternMatch :: struct {
    handle:             atom.Handle,
    score:              f64,                // Match quality score
    properties:         map[string]string,  // Matched properties
}

// =============================================================================
// META-PATTERN LIFECYCLE
// =============================================================================

// Create a meta-pattern
meta_pattern_create :: proc(
    name: string,
    type: MetaPatternType,
    allocator := context.allocator,
) -> ^MetaPattern {
    mp := new(MetaPattern, allocator)
    mp.name = strings.clone(name, allocator)
    mp.type = type
    mp.matches = make([dynamic]MetaPatternMatch, allocator)
    mp.allocator = allocator
    return mp
}

// Destroy a meta-pattern
meta_pattern_destroy :: proc(mp: ^MetaPattern) {
    if mp == nil {
        return
    }
    
    for &m in mp.matches {
        delete(m.properties)
    }
    delete(mp.matches)
    delete(mp.name, mp.allocator)
    free(mp, mp.allocator)
}

// =============================================================================
// PATTERN BUILDING
// =============================================================================

// Set target types for the pattern
meta_pattern_target_types :: proc(mp: ^MetaPattern, types: []types.CodeAtomType) {
    mp.criteria.target_types = types
}

// Set name constraints
meta_pattern_name_contains :: proc(mp: ^MetaPattern, substr: string) {
    mp.criteria.name_contains = substr
}

meta_pattern_name_prefix :: proc(mp: ^MetaPattern, prefix: string) {
    mp.criteria.name_prefix = prefix
}

meta_pattern_name_suffix :: proc(mp: ^MetaPattern, suffix: string) {
    mp.criteria.name_suffix = suffix
}

// Set call constraints
meta_pattern_must_call :: proc(mp: ^MetaPattern, procs: []string) {
    mp.criteria.must_call = procs
}

meta_pattern_must_not_call :: proc(mp: ^MetaPattern, procs: []string) {
    mp.criteria.must_not_call = procs
}

// Set output constraints (for rule patterns)
meta_pattern_produces :: proc(mp: ^MetaPattern, atom_types: []coreTypes.AtomType) {
    mp.criteria.produces_type = atom_types
}

// Set custom matcher
meta_pattern_set_matcher :: proc(
    mp: ^MetaPattern,
    matcher: proc(^MetaPattern, atom.Handle, ^atomspace.AtomSpace) -> bool,
) {
    mp.custom_matcher = matcher
}

// =============================================================================
// PATTERN MATCHING
// =============================================================================

// Execute meta-pattern against AtomSpace
meta_pattern_match_all :: proc(
    mp: ^MetaPattern,
    as: ^atomspace.AtomSpace,
) -> []MetaPatternMatch {
    clear(&mp.matches)
    mp.times_matched += 1
    
    // Get candidate atoms based on type
    candidates := get_candidates(mp, as)
    
    // Filter candidates
    for h in candidates {
        if match := evaluate_candidate(mp, h, as); match.score > 0 {
            append(&mp.matches, match)
            mp.total_matches += 1
        }
    }
    
    return mp.matches[:]
}

// Get candidate atoms for matching
get_candidates :: proc(mp: ^MetaPattern, as: ^atomspace.AtomSpace) -> []atom.Handle {
    result := make([dynamic]atom.Handle, context.temp_allocator)
    
    if mp.criteria.target_types != nil && len(mp.criteria.target_types) > 0 {
        // Get atoms of specified types
        for t in mp.criteria.target_types {
            base_type := coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(t))
            handles := atomspace.get_atoms_by_type(as, base_type, false)
            for h in handles {
                append(&result, h)
            }
        }
    } else {
        // Get all atoms
        it := atomspace.atomspace_iterator(as)
        for {
            _, h, ok := atomspace.atomspace_iterate(&it)
            if !ok { break }
            append(&result, h)
        }
    }
    
    return result[:]
}

// Evaluate a candidate against the pattern
evaluate_candidate :: proc(
    mp: ^MetaPattern,
    h: atom.Handle,
    as: ^atomspace.AtomSpace,
) -> MetaPatternMatch {
    match := MetaPatternMatch{
        handle = h,
        score = 0,
        properties = make(map[string]string, context.temp_allocator),
    }
    
    a, ok := atomspace.atomspace_get(as, h)
    if !ok {
        return match
    }
    
    // Custom matcher takes precedence
    if mp.custom_matcher != nil {
        if mp.custom_matcher(mp, h, as) {
            match.score = 1.0
        }
        return match
    }
    
    // Check criteria
    score: f64 = 0
    checks: f64 = 0
    
    // Name constraints
    if atom.atom_is_node(a) {
        name := atom.atom_get_name(a)
        
        if len(mp.criteria.name_contains) > 0 {
            checks += 1
            if strings.contains(name, mp.criteria.name_contains) {
                score += 1
                match.properties["name_match"] = "contains"
            }
        }
        
        if len(mp.criteria.name_prefix) > 0 {
            checks += 1
            if strings.has_prefix(name, mp.criteria.name_prefix) {
                score += 1
                match.properties["name_match"] = "prefix"
            }
        }
        
        if len(mp.criteria.name_suffix) > 0 {
            checks += 1
            if strings.has_suffix(name, mp.criteria.name_suffix) {
                score += 1
                match.properties["name_match"] = "suffix"
            }
        }
    }
    
    // Relationship constraints (check via incoming/outgoing links)
    if mp.criteria.must_call != nil {
        checks += f64(len(mp.criteria.must_call))
        
        // Get outgoing CallsLinks
        calls_type := coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.CALLS_LINK))
        
        for call_name in mp.criteria.must_call {
            // Check if this procedure calls the target
            incoming := atomspace.get_incoming_by_type(as, h, calls_type)
            for link_h in incoming {
                link_atom, link_ok := atomspace.atomspace_get(as, link_h)
                if link_ok {
                    // Check if caller matches
                    score += 1
                    break
                }
            }
        }
    }
    
    // Calculate final score
    if checks > 0 {
        match.score = score / checks
    } else {
        match.score = 1.0  // No constraints = match everything
    }
    
    return match
}

// =============================================================================
// PREDEFINED META-PATTERNS
// =============================================================================

// Create a pattern for procedures that modify AtomSpace
create_atomspace_modifiers_pattern :: proc(allocator := context.allocator) -> ^MetaPattern {
    mp := meta_pattern_create("atomspace_modifiers", .MODIFICATION_PATTERN, allocator)
    
    mp.criteria.target_types = []types.CodeAtomType{.PROCEDURE_NODE}
    mp.criteria.must_call = []string{
        "atomspace_add_node",
        "atomspace_add_link",
        "atomspace_remove",
        "add_node",
        "add_link",
        "remove_atom",
    }
    
    return mp
}

// Create a pattern for procedures that read from AtomSpace
create_atomspace_readers_pattern :: proc(allocator := context.allocator) -> ^MetaPattern {
    mp := meta_pattern_create("atomspace_readers", .DATA_FLOW_PATTERN, allocator)
    
    mp.criteria.target_types = []types.CodeAtomType{.PROCEDURE_NODE}
    mp.criteria.must_call = []string{
        "atomspace_get",
        "get_node",
        "get_atoms_by_type",
        "get_incoming",
        "atomspace_iterator",
    }
    
    return mp
}

// Create a pattern for rules that produce InheritanceLinks
create_inheritance_producers_pattern :: proc(allocator := context.allocator) -> ^MetaPattern {
    mp := meta_pattern_create("inheritance_producers", .RULE_PRODUCES_PATTERN, allocator)
    
    mp.criteria.produces_type = []coreTypes.AtomType{.INHERITANCE_LINK}
    
    return mp
}

// Create a pattern for recursive procedures
create_recursive_pattern :: proc(allocator := context.allocator) -> ^MetaPattern {
    mp := meta_pattern_create("recursive_procedures", .RECURSIVE_PATTERN, allocator)
    
    mp.criteria.target_types = []types.CodeAtomType{.PROCEDURE_NODE}
    mp.criteria.must_be_recursive = true
    
    // Custom matcher to detect recursion
    mp.custom_matcher = proc(mp: ^MetaPattern, h: atom.Handle, as: ^atomspace.AtomSpace) -> bool {
        // Check if procedure calls itself
        calls_type := coreTypes.AtomType(int(coreTypes.AtomType.USER_DEFINED_START) + int(types.CodeAtomType.CALLS_LINK))
        
        // Get all procedures this one calls
        it := atomspace.atomspace_iterator(as)
        for {
            link, link_h, ok := atomspace.atomspace_iterate(&it)
            if !ok { break }
            
            if link.atom_type == calls_type {
                outgoing := atom.atom_get_outgoing(link)
                if len(outgoing) >= 2 {
                    // Check if caller = callee
                    if atom.handle_equals(outgoing[0], h) && atom.handle_equals(outgoing[1], h) {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    return mp
}

// =============================================================================
// PATTERN COMPOSITION
// =============================================================================

// CompositeMetaPattern combines multiple patterns
CompositeMetaPattern :: struct {
    name:               string,
    components:         [dynamic]^MetaPattern,
    composition:        CompositionType,
    allocator:          mem.Allocator,
}

// CompositionType defines how patterns are combined
CompositionType :: enum {
    AND,        // All patterns must match
    OR,         // Any pattern must match
    NOT,        // Negation of first pattern
    SEQUENCE,   // Patterns must match in sequence (for call chains)
}

// Create composite pattern
composite_pattern_create :: proc(
    name: string,
    composition: CompositionType,
    allocator := context.allocator,
) -> ^CompositeMetaPattern {
    cp := new(CompositeMetaPattern, allocator)
    cp.name = strings.clone(name, allocator)
    cp.composition = composition
    cp.components = make([dynamic]^MetaPattern, allocator)
    cp.allocator = allocator
    return cp
}

// Add component pattern
composite_pattern_add :: proc(cp: ^CompositeMetaPattern, mp: ^MetaPattern) {
    append(&cp.components, mp)
}

// Execute composite pattern
composite_pattern_match :: proc(
    cp: ^CompositeMetaPattern,
    as: ^atomspace.AtomSpace,
) -> []MetaPatternMatch {
    if len(cp.components) == 0 {
        return nil
    }
    
    result := make([dynamic]MetaPatternMatch, context.temp_allocator)
    
    #partial switch cp.composition {
        case .AND:
            // Start with first pattern's matches
            first_matches := meta_pattern_match_all(cp.components[0], as)
            
            // Filter by subsequent patterns
            for match in first_matches {
                passes_all := true
                
                for i := 1; i < len(cp.components); i += 1 {
                    mp := cp.components[i]
                    evaluated := evaluate_candidate(mp, match.handle, as)
                    if evaluated.score <= 0 {
                        passes_all = false
                        break
                    }
                }
                
                if passes_all {
                    append(&result, match)
                }
            }
            
        case .OR:
            // Collect all matches from all patterns
            seen := make(map[atom.Handle]bool, context.temp_allocator)
            
            for mp in cp.components {
                matches := meta_pattern_match_all(mp, as)
                for match in matches {
                    if !(match.handle in seen) {
                        seen[match.handle] = true
                        append(&result, match)
                    }
                }
            }
            
        case .NOT:
            // Get all candidates that DON'T match first pattern
            first_matches := meta_pattern_match_all(cp.components[0], as)
            matched_set := make(map[atom.Handle]bool, context.temp_allocator)
            
            for match in first_matches {
                matched_set[match.handle] = true
            }
            
            // Return everything not in matched set
            it := atomspace.atomspace_iterator(as)
            for {
                _, h, ok := atomspace.atomspace_iterate(&it)
                if !ok { break }
                
                if !(h in matched_set) {
                    append(&result, MetaPatternMatch{handle = h, score = 1.0})
                }
            }
    }
    
    return result[:]
}

// =============================================================================
// PATTERN STATISTICS
// =============================================================================

// MetaPatternStats aggregates statistics about pattern matching
MetaPatternStats :: struct {
    total_patterns:     int,
    total_matches:      int,
    avg_match_score:    f64,
    match_distribution: map[MetaPatternType]int,
}

// Compute statistics for a set of meta-patterns
compute_meta_pattern_stats :: proc(
    patterns: []^MetaPattern,
    allocator := context.allocator,
) -> MetaPatternStats {
    stats := MetaPatternStats{
        match_distribution = make(map[MetaPatternType]int, allocator),
    }
    
    stats.total_patterns = len(patterns)
    total_score: f64 = 0
    
    for mp in patterns {
        stats.total_matches += len(mp.matches)
        
        for match in mp.matches {
            total_score += match.score
        }
        
        stats.match_distribution[mp.type] += len(mp.matches)
    }
    
    if stats.total_matches > 0 {
        stats.avg_match_score = total_score / f64(stats.total_matches)
    }
    
    return stats
}
