// OdinCog - OpenCog Implementation in Pure Odin
// Core Atom Module - Handle, TruthValue, AttentionValue, Atom structures
//
// This module defines the core data structures for atoms including:
// - Handle: Unique identifier for atoms
// - TruthValue: Probabilistic truth values
// - AttentionValue: Attention/importance values (ECAN)
// - Atom: Base structure for all atoms (nodes and links)

package odincog_atom

import "core:fmt"
import "core:strings"
import "core:math"
import "../types"

// =============================================================================
// HANDLE - Unique Atom Identifier
// =============================================================================

// Handle uniquely identifies an atom within an AtomSpace.
// Uses a generational index pattern for safe handle reuse.
Handle :: struct {
    idx: u32,      // Index into atom storage
    gen: u32,      // Generation counter for validity checking
}

// Invalid handle sentinel
INVALID_HANDLE :: Handle{idx = 0, gen = 0}

// Check if handle is valid (non-zero)
handle_is_valid :: proc(h: Handle) -> bool {
    return h.idx != 0
}

// Compare two handles for equality
handle_equals :: proc(a: Handle, b: Handle) -> bool {
    return a.idx == b.idx && a.gen == b.gen
}

// Hash a handle for use in maps
handle_hash :: proc(h: Handle) -> u64 {
    return u64(h.idx) | (u64(h.gen) << 32)
}

// =============================================================================
// TRUTH VALUE - Probabilistic Truth
// =============================================================================

// TruthValueType distinguishes different truth value representations
TruthValueType :: enum u8 {
    SIMPLE,         // (strength, confidence)
    COUNT,          // (strength, confidence, count)
    INDEFINITE,     // (lower, upper, confidence)
    FUZZY,          // Fuzzy truth value
    PROBABILISTIC,  // Full probability distribution
}

// SimpleTruthValue - Basic probabilistic truth
// strength: probability P(A) in [0,1]
// confidence: c = n/(n+k) where n is evidence count, k is a constant
SimpleTruthValue :: struct {
    strength:   f64,  // Mean probability
    confidence: f64,  // Confidence based on evidence
}

// CountTruthValue - Truth value with explicit count
CountTruthValue :: struct {
    strength:   f64,
    confidence: f64,
    count:      f64,  // Raw evidence count
}

// IndefiniteTruthValue - Probability interval
IndefiniteTruthValue :: struct {
    lower:      f64,  // Lower bound of probability
    upper:      f64,  // Upper bound of probability
    confidence: f64,
}

// TruthValue - Tagged union of all truth value types
TruthValue :: struct {
    type: TruthValueType,
    value: struct #raw_union {
        simple:     SimpleTruthValue,
        count:      CountTruthValue,
        indefinite: IndefiniteTruthValue,
    },
}

// Default truth value constants
DEFAULT_TV :: TruthValue{
    type = .SIMPLE,
    value = {simple = SimpleTruthValue{strength = 1.0, confidence = 0.0}},
}

TRUE_TV :: TruthValue{
    type = .SIMPLE,
    value = {simple = SimpleTruthValue{strength = 1.0, confidence = 0.9}},
}

FALSE_TV :: TruthValue{
    type = .SIMPLE,
    value = {simple = SimpleTruthValue{strength = 0.0, confidence = 0.9}},
}

// Create a simple truth value
make_stv :: proc(strength: f64, confidence: f64) -> TruthValue {
    return TruthValue{
        type = .SIMPLE,
        value = {simple = SimpleTruthValue{
            strength = clamp(strength, 0.0, 1.0),
            confidence = clamp(confidence, 0.0, 1.0),
        }},
    }
}

// Create a count truth value
make_ctv :: proc(strength: f64, confidence: f64, count: f64) -> TruthValue {
    return TruthValue{
        type = .COUNT,
        value = {count = CountTruthValue{
            strength = clamp(strength, 0.0, 1.0),
            confidence = clamp(confidence, 0.0, 1.0),
            count = max(count, 0.0),
        }},
    }
}

// Create an indefinite truth value
make_itv :: proc(lower: f64, upper: f64, confidence: f64) -> TruthValue {
    return TruthValue{
        type = .INDEFINITE,
        value = {indefinite = IndefiniteTruthValue{
            lower = clamp(lower, 0.0, 1.0),
            upper = clamp(upper, 0.0, 1.0),
            confidence = clamp(confidence, 0.0, 1.0),
        }},
    }
}

// Get strength from any truth value type
tv_get_strength :: proc(tv: TruthValue) -> f64 {
    switch tv.type {
        case .SIMPLE:
            return tv.value.simple.strength
        case .COUNT:
            return tv.value.count.strength
        case .INDEFINITE:
            // Mean of interval
            return (tv.value.indefinite.lower + tv.value.indefinite.upper) / 2.0
        case .FUZZY, .PROBABILISTIC:
            return tv.value.simple.strength  // Fallback
    }
    return 0.0
}

// Get confidence from any truth value type
tv_get_confidence :: proc(tv: TruthValue) -> f64 {
    switch tv.type {
        case .SIMPLE:
            return tv.value.simple.confidence
        case .COUNT:
            return tv.value.count.confidence
        case .INDEFINITE:
            return tv.value.indefinite.confidence
        case .FUZZY, .PROBABILISTIC:
            return tv.value.simple.confidence
    }
    return 0.0
}

// Check if truth value represents "true" (strength > 0.5, confidence > 0)
tv_is_true :: proc(tv: TruthValue) -> bool {
    return tv_get_strength(tv) > 0.5 && tv_get_confidence(tv) > 0.0
}

// Check if truth value is default (no information)
tv_is_default :: proc(tv: TruthValue) -> bool {
    return tv_get_confidence(tv) == 0.0
}

// Convert count to confidence using formula: c = n / (n + k)
// k is typically 800 in OpenCog
K_DEFAULT :: 800.0

count_to_confidence :: proc(count: f64, k: f64 = K_DEFAULT) -> f64 {
    return count / (count + k)
}

confidence_to_count :: proc(confidence: f64, k: f64 = K_DEFAULT) -> f64 {
    if confidence >= 1.0 {
        return math.INF_F64
    }
    return k * confidence / (1.0 - confidence)
}

// =============================================================================
// ATTENTION VALUE - ECAN Importance
// =============================================================================

// AttentionValue holds importance values for ECAN (Economic Attention Network)
AttentionValue :: struct {
    sti:  i16,  // Short-Term Importance (current relevance)
    lti:  i16,  // Long-Term Importance (learned importance)
    vlti: bool, // Very Long-Term Importance flag (never forget)
}

// Default attention value (neutral importance)
DEFAULT_AV :: AttentionValue{sti = 0, lti = 0, vlti = false}

// Attention focus thresholds
ATTENTIONAL_FOCUS_BOUNDARY :: i16(100)

// Check if atom is in attentional focus
av_in_focus :: proc(av: AttentionValue) -> bool {
    return av.sti >= ATTENTIONAL_FOCUS_BOUNDARY
}

// Create attention value
make_av :: proc(sti: i16, lti: i16, vlti: bool = false) -> AttentionValue {
    return AttentionValue{sti = sti, lti = lti, vlti = vlti}
}

// =============================================================================
// ATOM - Base Structure
// =============================================================================

// Atom is the base structure for all atoms in the AtomSpace.
// Each atom has a type, handle, truth value, and attention value.
Atom :: struct {
    handle:          Handle,           // Unique identifier
    atom_type:       types.AtomType,   // Type of this atom
    truth_value:     TruthValue,       // Probabilistic truth
    attention_value: AttentionValue,   // ECAN importance
    flags:           AtomFlags,        // Status flags
    
    // Atom-specific data (discriminated by atom_type)
    data: struct #raw_union {
        node: NodeData,
        link: LinkData,
    },
}

// AtomFlags for atom status
AtomFlags :: bit_set[AtomFlag; u8]

AtomFlag :: enum u8 {
    CHECKED,      // Already visited in traversal
    MARKED,       // Marked for some operation
    REMOVED,      // Tombstone flag
}

// NodeData holds node-specific fields
NodeData :: struct {
    name: string,   // Node name/label
}

// LinkData holds link-specific fields
LinkData :: struct {
    outgoing: [dynamic]Handle,  // Ordered list of target atom handles
}

// =============================================================================
// ATOM CONSTRUCTORS
// =============================================================================

// Create a new node atom
make_node :: proc(
    atom_type: types.AtomType,
    name: string,
    tv: TruthValue = DEFAULT_TV,
    av: AttentionValue = DEFAULT_AV,
    allocator := context.allocator,
) -> Atom {
    assert(types.is_node(atom_type), "make_node requires a node type")
    
    return Atom{
        handle = INVALID_HANDLE,  // Will be set when added to AtomSpace
        atom_type = atom_type,
        truth_value = tv,
        attention_value = av,
        flags = {},
        data = {node = NodeData{name = strings.clone(name, allocator)}},
    }
}

// Create a new link atom
make_link :: proc(
    atom_type: types.AtomType,
    outgoing: []Handle,
    tv: TruthValue = DEFAULT_TV,
    av: AttentionValue = DEFAULT_AV,
    allocator := context.allocator,
) -> Atom {
    assert(types.is_link(atom_type), "make_link requires a link type")
    
    out := make([dynamic]Handle, len(outgoing), allocator)
    copy(out[:], outgoing)
    
    return Atom{
        handle = INVALID_HANDLE,
        atom_type = atom_type,
        truth_value = tv,
        attention_value = av,
        flags = {},
        data = {link = LinkData{outgoing = out}},
    }
}

// =============================================================================
// ATOM ACCESSORS
// =============================================================================

// Check if atom is a node
atom_is_node :: proc(atom: ^Atom) -> bool {
    return types.is_node(atom.atom_type)
}

// Check if atom is a link
atom_is_link :: proc(atom: ^Atom) -> bool {
    return types.is_link(atom.atom_type)
}

// Get node name (returns empty string for links)
atom_get_name :: proc(atom: ^Atom) -> string {
    if atom_is_node(atom) {
        return atom.data.node.name
    }
    return ""
}

// Get link outgoing set (returns nil for nodes)
atom_get_outgoing :: proc(atom: ^Atom) -> []Handle {
    if atom_is_link(atom) {
        return atom.data.link.outgoing[:]
    }
    return nil
}

// Get link arity (number of targets)
atom_get_arity :: proc(atom: ^Atom) -> int {
    if atom_is_link(atom) {
        return len(atom.data.link.outgoing)
    }
    return 0
}

// Get specific outgoing handle by index
atom_get_outgoing_at :: proc(atom: ^Atom, idx: int) -> (Handle, bool) {
    if atom_is_link(atom) {
        outgoing := atom.data.link.outgoing
        if idx >= 0 && idx < len(outgoing) {
            return outgoing[idx], true
        }
    }
    return INVALID_HANDLE, false
}

// =============================================================================
// ATOM MEMORY MANAGEMENT
// =============================================================================

// Free atom resources
atom_destroy :: proc(atom: ^Atom, allocator := context.allocator) {
    if atom_is_node(atom) {
        delete(atom.data.node.name, allocator)
    } else if atom_is_link(atom) {
        delete(atom.data.link.outgoing)
    }
}

// =============================================================================
// ATOM STRING REPRESENTATION
// =============================================================================

// Format atom as string (for debugging)
atom_to_string :: proc(atom: ^Atom, allocator := context.allocator) -> string {
    builder := strings.builder_make(allocator)
    
    strings.write_string(&builder, "(")
    strings.write_string(&builder, types.type_name(atom.atom_type))
    
    if atom_is_node(atom) {
        strings.write_string(&builder, " \"")
        strings.write_string(&builder, atom.data.node.name)
        strings.write_string(&builder, "\"")
    } else if atom_is_link(atom) {
        for h in atom.data.link.outgoing {
            strings.write_string(&builder, fmt.tprintf(" #%d", h.idx))
        }
    }
    
    // Add truth value if non-default
    if !tv_is_default(atom.truth_value) {
        strings.write_string(&builder, fmt.tprintf(" (stv %.3f %.3f)",
            tv_get_strength(atom.truth_value),
            tv_get_confidence(atom.truth_value)))
    }
    
    strings.write_string(&builder, ")")
    
    return strings.to_string(builder)
}
