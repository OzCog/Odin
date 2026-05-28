// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Niche Construction
//
// This module implements niche construction - the ability of the agent
// to modify its environment (AtomSpace) to better suit its needs.
// This includes:
// - Affordance detection
// - Environment shaping
// - Scaffolding construction
// - Cache structures

package odincog_niche_construction

import "core:mem"
import "core:time"
import "core:math"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"
import "../../arena/state"

// =============================================================================
// AFFORDANCE TYPES
// =============================================================================

// AffordanceType categorizes what the environment affords
AffordanceType :: enum {
    // Information affordances
    QUERY_AFFORDANCE,           // Can query for information
    INFERENCE_AFFORDANCE,       // Can perform inference
    LEARNING_AFFORDANCE,        // Can learn from data
    
    // Structure affordances
    LINK_AFFORDANCE,            // Can create new links
    NODE_AFFORDANCE,            // Can create new nodes
    PATTERN_AFFORDANCE,         // Can match patterns
    
    // Navigation affordances
    TRAVERSE_AFFORDANCE,        // Can traverse links
    FOCUS_AFFORDANCE,           // Can focus attention
    SEARCH_AFFORDANCE,          // Can search for atoms
    
    // Modification affordances
    UPDATE_AFFORDANCE,          // Can update existing atoms
    DELETE_AFFORDANCE,          // Can delete atoms
    REORGANIZE_AFFORDANCE,      // Can reorganize structure
}

// Affordance represents a single environmental affordance
Affordance :: struct {
    type:               AffordanceType,
    
    // What atoms afford this action
    source_atoms:       [dynamic]atom.Handle,
    
    // Estimated utility
    utility:            f64,
    
    // Effort required
    effort:             f64,
    
    // Preconditions
    requires_focus:     bool,
    requires_attention: i16,
    
    // Properties
    properties:         map[string]f64,
}

// =============================================================================
// NICHE CONSTRUCTOR
// =============================================================================

// NicheConstructor manages environment modification
NicheConstructor :: struct {
    // Reference to world state
    world_state:        ^state.WorldState,
    atomspace:          ^atomspace.AtomSpace,
    
    // Detected affordances
    affordances:        [dynamic]^Affordance,
    
    // Construction history
    constructions:      [dynamic]Construction,
    
    // Scaffolding structures
    scaffolds:          [dynamic]^Scaffold,
    
    // Cache structures
    caches:             [dynamic]^Cache,
    
    // Configuration
    config:             NicheConfig,
    
    // Statistics
    stats:              NicheStats,
    
    allocator:          mem.Allocator,
}

// NicheConfig holds configuration
NicheConfig :: struct {
    // Affordance detection
    detect_affordances:     bool,
    affordance_threshold:   f64,
    
    // Construction limits
    max_scaffolds:          int,
    max_caches:             int,
    max_constructions:      int,
    
    // Decay rates
    scaffold_decay:         f64,
    cache_decay:            f64,
    
    // Utility thresholds
    min_scaffold_utility:   f64,
    min_cache_utility:      f64,
}

DEFAULT_NICHE_CONFIG :: NicheConfig{
    detect_affordances = true,
    affordance_threshold = 0.1,
    max_scaffolds = 50,
    max_caches = 20,
    max_constructions = 1000,
    scaffold_decay = 0.99,
    cache_decay = 0.95,
    min_scaffold_utility = 0.1,
    min_cache_utility = 0.2,
}

// NicheStats tracks construction statistics
NicheStats :: struct {
    total_constructions:    int,
    active_scaffolds:       int,
    active_caches:          int,
    total_affordances:      int,
    avg_utility_gain:       f64,
}

// Construction records a modification made
Construction :: struct {
    timestamp:          time.Time,
    type:               ConstructionType,
    
    // What was created/modified
    atoms_created:      []atom.Handle,
    atoms_modified:     []atom.Handle,
    
    // Purpose
    purpose:            string,
    
    // Outcome
    utility_before:     f64,
    utility_after:      f64,
    success:            bool,
}

// ConstructionType indicates what kind of modification
ConstructionType :: enum {
    SCAFFOLD_CREATION,
    CACHE_CREATION,
    LINK_CREATION,
    NODE_CREATION,
    REORGANIZATION,
    CLEANUP,
}

// =============================================================================
// NICHE CONSTRUCTOR LIFECYCLE
// =============================================================================

// Create niche constructor
niche_constructor_create :: proc(
    ws: ^state.WorldState,
    config: NicheConfig = DEFAULT_NICHE_CONFIG,
    allocator := context.allocator,
) -> ^NicheConstructor {
    nc := new(NicheConstructor, allocator)
    
    nc.world_state = ws
    nc.atomspace = ws.atomspace
    nc.config = config
    nc.affordances = make([dynamic]^Affordance, allocator)
    nc.constructions = make([dynamic]Construction, allocator)
    nc.scaffolds = make([dynamic]^Scaffold, allocator)
    nc.caches = make([dynamic]^Cache, allocator)
    nc.allocator = allocator
    
    return nc
}

// Destroy niche constructor
niche_constructor_destroy :: proc(nc: ^NicheConstructor) {
    if nc == nil {
        return
    }
    
    for a in nc.affordances {
        affordance_destroy(a, nc.allocator)
    }
    delete(nc.affordances)
    
    for s in nc.scaffolds {
        scaffold_destroy(s)
    }
    delete(nc.scaffolds)
    
    for c in nc.caches {
        cache_destroy(c)
    }
    delete(nc.caches)
    
    delete(nc.constructions)
    
    free(nc, nc.allocator)
}

// Destroy an affordance
affordance_destroy :: proc(a: ^Affordance, allocator: mem.Allocator) {
    if a == nil {
        return
    }
    delete(a.source_atoms)
    delete(a.properties)
    free(a, allocator)
}

// =============================================================================
// AFFORDANCE DETECTION
// =============================================================================

// Detect affordances in the current environment
niche_detect_affordances :: proc(nc: ^NicheConstructor) -> []^Affordance {
    // Clear old affordances
    for a in nc.affordances {
        affordance_destroy(a, nc.allocator)
    }
    clear(&nc.affordances)
    
    // Detect different types of affordances
    detect_query_affordances(nc)
    detect_inference_affordances(nc)
    detect_structure_affordances(nc)
    detect_navigation_affordances(nc)
    
    nc.stats.total_affordances = len(nc.affordances)
    
    return nc.affordances[:]
}

// Detect query affordances
detect_query_affordances :: proc(nc: ^NicheConstructor) {
    // Find atoms that can be queried (nodes with incoming links)
    it := atomspace.atomspace_iterator(nc.atomspace)
    
    for {
        a, h, ok := atomspace.atomspace_iterate(&it)
        if !ok { break }
        
        if atom.atom_is_node(a) {
            incoming := atomspace.get_incoming(nc.atomspace, h)
            if len(incoming) > 0 {
                affordance := new(Affordance, nc.allocator)
                affordance.type = .QUERY_AFFORDANCE
                affordance.source_atoms = make([dynamic]atom.Handle, nc.allocator)
                append(&affordance.source_atoms, h)
                affordance.utility = f64(len(incoming)) * 0.1
                affordance.effort = 1.0
                affordance.properties = make(map[string]f64, nc.allocator)
                affordance.properties["incoming_count"] = f64(len(incoming))
                
                if affordance.utility >= nc.config.affordance_threshold {
                    append(&nc.affordances, affordance)
                } else {
                    affordance_destroy(affordance, nc.allocator)
                }
            }
        }
    }
}

// Detect inference affordances
detect_inference_affordances :: proc(nc: ^NicheConstructor) {
    // Find inference opportunities (links that could support reasoning)
    inference_types := [?]types.AtomType{
        .INHERITANCE_LINK, .IMPLICATION_LINK, .EVALUATION_LINK,
    }
    
    for inf_type in inference_types {
        handles := atomspace.get_atoms_by_type(nc.atomspace, inf_type, false)
        
        if len(handles) > 0 {
            affordance := new(Affordance, nc.allocator)
            affordance.type = .INFERENCE_AFFORDANCE
            affordance.source_atoms = make([dynamic]atom.Handle, nc.allocator)
            
            for h in handles {
                append(&affordance.source_atoms, h)
            }
            
            affordance.utility = f64(len(handles)) * 0.2
            affordance.effort = f64(len(handles)) * 0.5
            affordance.properties = make(map[string]f64, nc.allocator)
            affordance.properties["link_count"] = f64(len(handles))
            
            append(&nc.affordances, affordance)
        }
    }
}

// Detect structure affordances
detect_structure_affordances :: proc(nc: ^NicheConstructor) {
    stats := atomspace.atomspace_stats(nc.atomspace)
    
    // Creating links is more useful when there are many nodes
    if stats.total_nodes > 10 {
        affordance := new(Affordance, nc.allocator)
        affordance.type = .LINK_AFFORDANCE
        affordance.source_atoms = make([dynamic]atom.Handle, nc.allocator)
        affordance.utility = f64(stats.total_nodes) * 0.05
        affordance.effort = 2.0
        affordance.properties = make(map[string]f64, nc.allocator)
        affordance.properties["potential_links"] = f64(stats.total_nodes * (stats.total_nodes - 1) / 2)
        
        append(&nc.affordances, affordance)
    }
}

// Detect navigation affordances
detect_navigation_affordances :: proc(nc: ^NicheConstructor) {
    // Focus affordance based on attention distribution
    summary := nc.world_state.attention_summary
    
    if summary.atoms_in_focus > 0 {
        affordance := new(Affordance, nc.allocator)
        affordance.type = .FOCUS_AFFORDANCE
        affordance.source_atoms = make([dynamic]atom.Handle, nc.allocator)
        
        for h in summary.top_atoms {
            if atom.handle_is_valid(h) {
                append(&affordance.source_atoms, h)
            }
        }
        
        affordance.utility = f64(summary.atoms_in_focus) * 0.3
        affordance.effort = 0.5
        affordance.properties = make(map[string]f64, nc.allocator)
        
        append(&nc.affordances, affordance)
    }
}

// =============================================================================
// SCAFFOLD STRUCTURES
// =============================================================================

// Scaffold is a temporary structure to aid cognition
Scaffold :: struct {
    name:               string,
    type:               ScaffoldType,
    
    // Atoms that form the scaffold
    atoms:              [dynamic]atom.Handle,
    
    // What the scaffold supports
    supports:           [dynamic]atom.Handle,
    
    // Lifecycle
    created_at:         time.Time,
    last_used:          time.Time,
    use_count:          int,
    
    // Utility
    utility:            f64,
    decay_rate:         f64,
    
    allocator:          mem.Allocator,
}

// ScaffoldType indicates the scaffold's purpose
ScaffoldType :: enum {
    INDEX_SCAFFOLD,         // Index for fast lookup
    SUMMARY_SCAFFOLD,       // Summarizes complex structure
    BRIDGE_SCAFFOLD,        // Connects distant atoms
    CONTEXT_SCAFFOLD,       // Provides context for inference
    WORKING_SCAFFOLD,       // Temporary working memory
}

// Create a scaffold
scaffold_create :: proc(
    name: string,
    type: ScaffoldType,
    allocator := context.allocator,
) -> ^Scaffold {
    s := new(Scaffold, allocator)
    s.name = name
    s.type = type
    s.atoms = make([dynamic]atom.Handle, allocator)
    s.supports = make([dynamic]atom.Handle, allocator)
    s.created_at = time.now()
    s.last_used = time.now()
    s.utility = 1.0
    s.decay_rate = 0.99
    s.allocator = allocator
    return s
}

// Destroy a scaffold
scaffold_destroy :: proc(s: ^Scaffold) {
    if s == nil {
        return
    }
    delete(s.atoms)
    delete(s.supports)
    free(s, s.allocator)
}

// Use a scaffold (updates usage stats)
scaffold_use :: proc(s: ^Scaffold) {
    s.last_used = time.now()
    s.use_count += 1
    s.utility = min(s.utility + 0.1, 1.0)
}

// Decay scaffold utility
scaffold_decay :: proc(s: ^Scaffold) {
    s.utility *= s.decay_rate
}

// =============================================================================
// CACHE STRUCTURES
// =============================================================================

// Cache stores frequently accessed patterns/results
Cache :: struct {
    name:               string,
    
    // What's cached
    pattern:            []atom.Handle,  // Pattern that was matched
    results:            [dynamic][]atom.Handle,  // Cached results
    
    // Lifecycle
    created_at:         time.Time,
    last_hit:           time.Time,
    hit_count:          int,
    miss_count:         int,
    
    // Cache policy
    max_entries:        int,
    eviction_policy:    EvictionPolicy,
    
    // Utility
    utility:            f64,
    
    allocator:          mem.Allocator,
}

// EvictionPolicy for cache management
EvictionPolicy :: enum {
    LRU,            // Least recently used
    LFU,            // Least frequently used
    FIFO,           // First in, first out
}

// Create a cache
cache_create :: proc(
    name: string,
    max_entries: int = 100,
    allocator := context.allocator,
) -> ^Cache {
    c := new(Cache, allocator)
    c.name = name
    c.results = make([dynamic][]atom.Handle, allocator)
    c.created_at = time.now()
    c.last_hit = time.now()
    c.max_entries = max_entries
    c.eviction_policy = .LRU
    c.utility = 1.0
    c.allocator = allocator
    return c
}

// Destroy a cache
cache_destroy :: proc(c: ^Cache) {
    if c == nil {
        return
    }
    for result in c.results {
        delete(result, c.allocator)
    }
    delete(c.results)
    delete(c.pattern, c.allocator)
    free(c, c.allocator)
}

// Cache lookup
cache_lookup :: proc(c: ^Cache, pattern: []atom.Handle) -> ([][]atom.Handle, bool) {
    // Simple pattern matching
    if len(c.pattern) != len(pattern) {
        c.miss_count += 1
        return nil, false
    }
    
    matches := true
    for i := 0; i < len(pattern); i += 1 {
        if !atom.handle_equals(c.pattern[i], pattern[i]) {
            matches = false
            break
        }
    }
    
    if matches {
        c.hit_count += 1
        c.last_hit = time.now()
        c.utility = min(c.utility + 0.05, 1.0)
        return c.results[:], true
    }
    
    c.miss_count += 1
    return nil, false
}

// Cache store
cache_store :: proc(c: ^Cache, pattern: []atom.Handle, result: []atom.Handle) {
    // Store pattern if not set
    if c.pattern == nil {
        c.pattern = make([]atom.Handle, len(pattern), c.allocator)
        copy(c.pattern, pattern)
    }
    
    // Check capacity
    if len(c.results) >= c.max_entries {
        // Evict based on policy
        cache_evict(c)
    }
    
    // Store result
    result_copy := make([]atom.Handle, len(result), c.allocator)
    copy(result_copy, result)
    append(&c.results, result_copy)
}

// Evict entries based on policy
cache_evict :: proc(c: ^Cache) {
    if len(c.results) == 0 {
        return
    }
    
    #partial switch c.eviction_policy {
        case .FIFO:
            // Remove oldest
            delete(c.results[0], c.allocator)
            ordered_remove(&c.results, 0)
        case .LRU, .LFU:
            // Simple implementation: remove first
            delete(c.results[0], c.allocator)
            ordered_remove(&c.results, 0)
    }
}

// Get cache hit rate
cache_hit_rate :: proc(c: ^Cache) -> f64 {
    total := c.hit_count + c.miss_count
    if total == 0 {
        return 0
    }
    return f64(c.hit_count) / f64(total)
}

// =============================================================================
// CONSTRUCTION OPERATIONS
// =============================================================================

// Create an index scaffold for a set of atoms
niche_create_index_scaffold :: proc(
    nc: ^NicheConstructor,
    atoms: []atom.Handle,
    name: string,
) -> ^Scaffold {
    scaffold := scaffold_create(name, .INDEX_SCAFFOLD, nc.allocator)
    
    // Create anchor node for the index
    anchor_h, _ := atomspace.add_node(
        nc.atomspace,
        .ANCHOR_NODE,
        name,
    )
    append(&scaffold.atoms, anchor_h)
    
    // Link indexed atoms to anchor
    for h in atoms {
        link_h, _ := atomspace.add_link(
            nc.atomspace,
            .MEMBER_LINK,
            []atom.Handle{h, anchor_h},
        )
        append(&scaffold.atoms, link_h)
        append(&scaffold.supports, h)
    }
    
    append(&nc.scaffolds, scaffold)
    nc.stats.active_scaffolds += 1
    
    // Record construction
    record_construction(nc, .SCAFFOLD_CREATION, scaffold.atoms[:], nil, name)
    
    return scaffold
}

// Create a bridge scaffold between distant atoms
niche_create_bridge_scaffold :: proc(
    nc: ^NicheConstructor,
    source: atom.Handle,
    target: atom.Handle,
    name: string,
) -> ^Scaffold {
    scaffold := scaffold_create(name, .BRIDGE_SCAFFOLD, nc.allocator)
    
    // Create bridge link
    bridge_h, _ := atomspace.add_link(
        nc.atomspace,
        .ASSOCIATIVE_LINK,
        []atom.Handle{source, target},
    )
    
    append(&scaffold.atoms, bridge_h)
    append(&scaffold.supports, source)
    append(&scaffold.supports, target)
    
    append(&nc.scaffolds, scaffold)
    nc.stats.active_scaffolds += 1
    
    record_construction(nc, .SCAFFOLD_CREATION, scaffold.atoms[:], nil, name)
    
    return scaffold
}

// Create a pattern cache
niche_create_cache :: proc(
    nc: ^NicheConstructor,
    name: string,
    max_entries: int = 100,
) -> ^Cache {
    cache := cache_create(name, max_entries, nc.allocator)
    
    append(&nc.caches, cache)
    nc.stats.active_caches += 1
    
    record_construction(nc, .CACHE_CREATION, nil, nil, name)
    
    return cache
}

// Record a construction event
record_construction :: proc(
    nc: ^NicheConstructor,
    type: ConstructionType,
    created: []atom.Handle,
    modified: []atom.Handle,
    purpose: string,
) {
    record := Construction{
        timestamp = time.now(),
        type = type,
        atoms_created = created,
        atoms_modified = modified,
        purpose = purpose,
        success = true,
    }
    
    append(&nc.constructions, record)
    nc.stats.total_constructions += 1
    
    // Prune history
    if len(nc.constructions) > nc.config.max_constructions {
        remove_range(&nc.constructions, 0, len(nc.constructions) - nc.config.max_constructions)
    }
}

// =============================================================================
// NICHE MAINTENANCE
// =============================================================================

// Run maintenance cycle (decay, cleanup)
niche_maintenance :: proc(nc: ^NicheConstructor) {
    // Decay scaffolds
    for scaffold in nc.scaffolds {
        scaffold_decay(scaffold)
    }
    
    // Remove low-utility scaffolds
    i := 0
    for i < len(nc.scaffolds) {
        if nc.scaffolds[i].utility < nc.config.min_scaffold_utility {
            // Remove scaffold atoms from atomspace
            for h in nc.scaffolds[i].atoms {
                atomspace.remove_atom(nc.atomspace, h, false)
            }
            
            scaffold_destroy(nc.scaffolds[i])
            unordered_remove(&nc.scaffolds, i)
            nc.stats.active_scaffolds -= 1
        } else {
            i += 1
        }
    }
    
    // Decay caches
    for cache in nc.caches {
        cache.utility *= nc.config.cache_decay
    }
    
    // Remove low-utility caches
    i = 0
    for i < len(nc.caches) {
        if nc.caches[i].utility < nc.config.min_cache_utility {
            cache_destroy(nc.caches[i])
            unordered_remove(&nc.caches, i)
            nc.stats.active_caches -= 1
        } else {
            i += 1
        }
    }
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Get highest utility affordance
niche_best_affordance :: proc(nc: ^NicheConstructor) -> ^Affordance {
    if len(nc.affordances) == 0 {
        return nil
    }
    
    best: ^Affordance = nc.affordances[0]
    best_ratio: f64 = 0
    
    for a in nc.affordances {
        ratio := a.utility / a.effort
        if ratio > best_ratio {
            best_ratio = ratio
            best = a
        }
    }
    
    return best
}

// Find scaffold by name
niche_find_scaffold :: proc(nc: ^NicheConstructor, name: string) -> ^Scaffold {
    for s in nc.scaffolds {
        if s.name == name {
            return s
        }
    }
    return nil
}

// Find cache by name
niche_find_cache :: proc(nc: ^NicheConstructor, name: string) -> ^Cache {
    for c in nc.caches {
        if c.name == name {
            return c
        }
    }
    return nil
}

// Get niche statistics
niche_get_stats :: proc(nc: ^NicheConstructor) -> NicheStats {
    return nc.stats
}
