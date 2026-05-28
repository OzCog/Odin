// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Stigmergic Communication
//
// This module implements stigmergy - indirect coordination through
// environmental modification. The agent leaves "traces" on atoms
// that influence future behavior:
// - Pheromone-like attention traces
// - Environmental cues
// - Persistent marks
// - Trace decay and reinforcement

package odincog_stigmergy

import "core:mem"
import "core:time"
import "core:math"
import "../../core/atom"
import "../../core/atomspace"
import "../../arena/state"

// =============================================================================
// STIGMERGY TYPES
// =============================================================================

// TraceType categorizes different types of traces
TraceType :: enum {
    // Attention-based traces
    ATTENTION_PHEROMONE,    // Left by focusing attention
    EXPLORATION_TRAIL,      // Left during exploration
    SUCCESS_MARKER,         // Marks successful outcomes
    
    // Communication traces
    GOAL_SIGNAL,            // Signals active goals
    OBSTACLE_WARNING,       // Warns of obstacles/failures
    RESOURCE_INDICATOR,     // Indicates available resources
    
    // Coordination traces
    CLAIM_MARKER,           // Claims resource for processing
    PROGRESS_MARKER,        // Marks progress state
    COMPLETION_MARKER,      // Marks completed operations
    
    // Meta-level traces
    IMPORTANCE_TRACE,       // Indicates importance
    RECENCY_TRACE,          // Indicates recent access
    UTILITY_TRACE,          // Indicates utility value
}

// Trace represents a stigmergic mark on an atom
Trace :: struct {
    type:               TraceType,
    target:             atom.Handle,
    
    // Trace properties
    intensity:          f64,        // Current strength (0-1)
    initial_intensity:  f64,        // Starting strength
    
    // Temporal properties
    created_at:         time.Time,
    last_reinforced:    time.Time,
    reinforcement_count: int,
    
    // Decay properties
    decay_rate:         f64,        // Per-tick decay
    half_life:          int,        // Ticks until half intensity
    min_intensity:      f64,        // Below this, trace is removed
    
    // Source information
    source:             string,     // What created this trace
    
    // Additional data
    data:               map[string]f64,
}

// TraceLayer represents all traces of one type
TraceLayer :: struct {
    type:               TraceType,
    traces:             map[atom.Handle]^Trace,
    
    // Layer properties
    default_decay:      f64,
    default_intensity:  f64,
    max_traces:         int,
    
    // Statistics
    total_intensity:    f64,
    active_count:       int,
    
    allocator:          mem.Allocator,
}

// =============================================================================
// STIGMERGY MANAGER
// =============================================================================

// StigmergyManager handles all stigmergic traces
StigmergyManager :: struct {
    // Reference to world state
    world_state:        ^state.WorldState,
    atomspace:          ^atomspace.AtomSpace,
    
    // Trace layers (one per type)
    layers:             map[TraceType]^TraceLayer,
    
    // Configuration
    config:             StigmergyConfig,
    
    // Statistics
    stats:              StigmergyStats,
    
    // State
    tick_count:         u64,
    
    allocator:          mem.Allocator,
}

// StigmergyConfig holds configuration
StigmergyConfig :: struct {
    // Decay settings
    default_decay_rate:     f64,
    min_trace_intensity:    f64,
    
    // Limits
    max_traces_per_layer:   int,
    max_layers:             int,
    
    // Reinforcement
    reinforcement_boost:    f64,
    max_reinforcements:     int,
    
    // Diffusion
    enable_diffusion:       bool,
    diffusion_rate:         f64,
}

DEFAULT_STIGMERGY_CONFIG :: StigmergyConfig{
    default_decay_rate = 0.99,
    min_trace_intensity = 0.01,
    max_traces_per_layer = 10000,
    max_layers = 12,  // One per TraceType
    reinforcement_boost = 0.2,
    max_reinforcements = 10,
    enable_diffusion = true,
    diffusion_rate = 0.1,
}

// StigmergyStats tracks statistics
StigmergyStats :: struct {
    total_traces:           int,
    active_traces:          int,
    traces_created:         int,
    traces_removed:         int,
    traces_reinforced:      int,
    total_diffusions:       int,
}

// =============================================================================
// LIFECYCLE
// =============================================================================

// Create stigmergy manager
stigmergy_manager_create :: proc(
    ws: ^state.WorldState,
    config: StigmergyConfig = DEFAULT_STIGMERGY_CONFIG,
    allocator := context.allocator,
) -> ^StigmergyManager {
    sm := new(StigmergyManager, allocator)
    
    sm.world_state = ws
    sm.atomspace = ws.atomspace
    sm.config = config
    sm.allocator = allocator
    sm.layers = make(map[TraceType]^TraceLayer, allocator)
    
    // Create layers for each trace type
    trace_types := [?]TraceType{
        .ATTENTION_PHEROMONE, .EXPLORATION_TRAIL, .SUCCESS_MARKER,
        .GOAL_SIGNAL, .OBSTACLE_WARNING, .RESOURCE_INDICATOR,
        .CLAIM_MARKER, .PROGRESS_MARKER, .COMPLETION_MARKER,
        .IMPORTANCE_TRACE, .RECENCY_TRACE, .UTILITY_TRACE,
    }
    
    for tt in trace_types {
        layer := trace_layer_create(tt, config.max_traces_per_layer, allocator)
        layer.default_decay = config.default_decay_rate
        sm.layers[tt] = layer
    }
    
    return sm
}

// Destroy stigmergy manager
stigmergy_manager_destroy :: proc(sm: ^StigmergyManager) {
    if sm == nil {
        return
    }
    
    for _, layer in sm.layers {
        trace_layer_destroy(layer)
    }
    delete(sm.layers)
    
    free(sm, sm.allocator)
}

// Create trace layer
trace_layer_create :: proc(
    type: TraceType,
    max_traces: int,
    allocator: mem.Allocator,
) -> ^TraceLayer {
    layer := new(TraceLayer, allocator)
    
    layer.type = type
    layer.traces = make(map[atom.Handle]^Trace, allocator)
    layer.default_decay = 0.99
    layer.default_intensity = 1.0
    layer.max_traces = max_traces
    layer.allocator = allocator
    
    return layer
}

// Destroy trace layer
trace_layer_destroy :: proc(layer: ^TraceLayer) {
    if layer == nil {
        return
    }
    
    for _, trace in layer.traces {
        trace_destroy(trace, layer.allocator)
    }
    delete(layer.traces)
    
    free(layer, layer.allocator)
}

// Destroy trace
trace_destroy :: proc(trace: ^Trace, allocator: mem.Allocator) {
    if trace == nil {
        return
    }
    delete(trace.data)
    free(trace, allocator)
}

// =============================================================================
// TRACE OPERATIONS
// =============================================================================

// Leave a trace on an atom
stigmergy_leave_trace :: proc(
    sm: ^StigmergyManager,
    type: TraceType,
    target: atom.Handle,
    intensity: f64 = 1.0,
    source: string = "",
) -> ^Trace {
    layer, ok := sm.layers[type]
    if !ok {
        return nil
    }
    
    // Check if trace already exists
    existing, exists := layer.traces[target]
    if exists {
        // Reinforce existing trace
        stigmergy_reinforce_trace(sm, existing)
        return existing
    }
    
    // Check capacity
    if layer.active_count >= layer.max_traces {
        // Remove weakest trace
        remove_weakest_trace(layer)
    }
    
    // Create new trace
    trace := new(Trace, sm.allocator)
    trace.type = type
    trace.target = target
    trace.intensity = intensity
    trace.initial_intensity = intensity
    trace.created_at = time.now()
    trace.last_reinforced = time.now()
    trace.decay_rate = layer.default_decay
    trace.half_life = compute_half_life(layer.default_decay)
    trace.min_intensity = sm.config.min_trace_intensity
    trace.source = source
    trace.data = make(map[string]f64, sm.allocator)
    
    layer.traces[target] = trace
    layer.active_count += 1
    layer.total_intensity += intensity
    
    sm.stats.traces_created += 1
    sm.stats.total_traces += 1
    sm.stats.active_traces += 1
    
    return trace
}

// Reinforce a trace
stigmergy_reinforce_trace :: proc(sm: ^StigmergyManager, trace: ^Trace) {
    if trace == nil {
        return
    }
    
    if trace.reinforcement_count >= sm.config.max_reinforcements {
        return
    }
    
    // Boost intensity
    old_intensity := trace.intensity
    trace.intensity = min(1.0, trace.intensity + sm.config.reinforcement_boost)
    trace.last_reinforced = time.now()
    trace.reinforcement_count += 1
    
    // Update layer statistics
    layer, ok := sm.layers[trace.type]
    if ok {
        layer.total_intensity += trace.intensity - old_intensity
    }
    
    sm.stats.traces_reinforced += 1
}

// Remove a trace
stigmergy_remove_trace :: proc(sm: ^StigmergyManager, type: TraceType, target: atom.Handle) {
    layer, ok := sm.layers[type]
    if !ok {
        return
    }
    
    trace, exists := layer.traces[target]
    if !exists {
        return
    }
    
    layer.total_intensity -= trace.intensity
    layer.active_count -= 1
    delete_key(&layer.traces, target)
    
    trace_destroy(trace, layer.allocator)
    
    sm.stats.traces_removed += 1
    sm.stats.active_traces -= 1
}

// Remove weakest trace from layer
remove_weakest_trace :: proc(layer: ^TraceLayer) {
    if layer.active_count == 0 {
        return
    }
    
    weakest: ^Trace = nil
    weakest_handle: atom.Handle
    
    for handle, trace in layer.traces {
        if weakest == nil || trace.intensity < weakest.intensity {
            weakest = trace
            weakest_handle = handle
        }
    }
    
    if weakest != nil {
        layer.total_intensity -= weakest.intensity
        layer.active_count -= 1
        delete_key(&layer.traces, weakest_handle)
        trace_destroy(weakest, layer.allocator)
    }
}

// Compute half-life from decay rate
compute_half_life :: proc(decay_rate: f64) -> int {
    if decay_rate >= 1.0 || decay_rate <= 0 {
        return 1000000  // Very long
    }
    return int(math.ln(0.5) / math.ln(decay_rate))
}

// =============================================================================
// TRACE QUERIES
// =============================================================================

// Get trace intensity for an atom
stigmergy_get_intensity :: proc(
    sm: ^StigmergyManager,
    type: TraceType,
    target: atom.Handle,
) -> f64 {
    layer, ok := sm.layers[type]
    if !ok {
        return 0
    }
    
    trace, exists := layer.traces[target]
    if !exists {
        return 0
    }
    
    return trace.intensity
}

// Get total intensity across all trace types
stigmergy_get_total_intensity :: proc(sm: ^StigmergyManager, target: atom.Handle) -> f64 {
    total: f64 = 0
    
    for _, layer in sm.layers {
        trace, exists := layer.traces[target]
        if exists {
            total += trace.intensity
        }
    }
    
    return total
}

// Get all traces for an atom
stigmergy_get_traces :: proc(sm: ^StigmergyManager, target: atom.Handle) -> []^Trace {
    traces := make([dynamic]^Trace, sm.allocator)
    
    for _, layer in sm.layers {
        trace, exists := layer.traces[target]
        if exists {
            append(&traces, trace)
        }
    }
    
    return traces[:]
}

// Get all atoms with traces of a type
stigmergy_get_marked_atoms :: proc(sm: ^StigmergyManager, type: TraceType) -> []atom.Handle {
    layer, ok := sm.layers[type]
    if !ok {
        return nil
    }
    
    handles := make([dynamic]atom.Handle, sm.allocator)
    
    for handle, _ in layer.traces {
        append(&handles, handle)
    }
    
    return handles[:]
}

// Get top N atoms by trace intensity
stigmergy_get_top_atoms :: proc(
    sm: ^StigmergyManager,
    type: TraceType,
    n: int,
) -> []atom.Handle {
    layer, ok := sm.layers[type]
    if !ok {
        return nil
    }
    
    // Collect all traces with handles
    TracePair :: struct {
        handle:     atom.Handle,
        intensity:  f64,
    }
    
    pairs := make([dynamic]TracePair, sm.allocator)
    defer delete(pairs)
    
    for handle, trace in layer.traces {
        append(&pairs, TracePair{handle, trace.intensity})
    }
    
    // Sort by intensity (descending) - simple selection sort for small n
    result := make([dynamic]atom.Handle, sm.allocator)
    
    for i := 0; i < min(n, len(pairs)); i += 1 {
        max_idx := i
        for j := i + 1; j < len(pairs); j += 1 {
            if pairs[j].intensity > pairs[max_idx].intensity {
                max_idx = j
            }
        }
        if max_idx != i {
            pairs[i], pairs[max_idx] = pairs[max_idx], pairs[i]
        }
        append(&result, pairs[i].handle)
    }
    
    return result[:]
}

// =============================================================================
// DECAY AND DIFFUSION
// =============================================================================

// Decay all traces
stigmergy_decay :: proc(sm: ^StigmergyManager) {
    for _, layer in sm.layers {
        trace_layer_decay(layer, sm.config.min_trace_intensity)
    }
}

// Decay traces in a layer
trace_layer_decay :: proc(layer: ^TraceLayer, min_intensity: f64) {
    to_remove := make([dynamic]atom.Handle, layer.allocator)
    defer delete(to_remove)
    
    new_total: f64 = 0
    
    for handle, trace in layer.traces {
        trace.intensity *= trace.decay_rate
        
        if trace.intensity < min_intensity {
            append(&to_remove, handle)
        } else {
            new_total += trace.intensity
        }
    }
    
    // Remove decayed traces
    for handle in to_remove {
        trace := layer.traces[handle]
        delete_key(&layer.traces, handle)
        trace_destroy(trace, layer.allocator)
        layer.active_count -= 1
    }
    
    layer.total_intensity = new_total
}

// Diffuse traces to neighboring atoms
stigmergy_diffuse :: proc(sm: ^StigmergyManager) {
    if !sm.config.enable_diffusion {
        return
    }
    
    // Collect diffusion updates
    DiffusionUpdate :: struct {
        type:       TraceType,
        target:     atom.Handle,
        amount:     f64,
    }
    
    updates := make([dynamic]DiffusionUpdate, sm.allocator)
    defer delete(updates)
    
    for trace_type, layer in sm.layers {
        for handle, trace in layer.traces {
            // Skip weak traces
            if trace.intensity < 0.1 {
                continue
            }
            
            // Get neighboring atoms (via links)
            neighbors := get_neighbors(sm.atomspace, handle)
            
            if len(neighbors) > 0 {
                diffusion_amount := trace.intensity * sm.config.diffusion_rate / f64(len(neighbors))
                
                for neighbor in neighbors {
                    append(&updates, DiffusionUpdate{
                        type = trace_type,
                        target = neighbor,
                        amount = diffusion_amount,
                    })
                }
            }
        }
    }
    
    // Apply diffusion updates
    for update in updates {
        existing := stigmergy_get_intensity(sm, update.type, update.target)
        
        if existing > 0 {
            // Reinforce existing trace
            layer := sm.layers[update.type]
            if trace, ok := layer.traces[update.target]; ok {
                old := trace.intensity
                trace.intensity = min(1.0, trace.intensity + update.amount * 0.5)
                layer.total_intensity += trace.intensity - old
            }
        } else if update.amount > sm.config.min_trace_intensity {
            // Create new weak trace
            stigmergy_leave_trace(sm, update.type, update.target, update.amount, "diffusion")
        }
        
        sm.stats.total_diffusions += 1
    }
}

// Get neighboring atoms (connected via links)
get_neighbors :: proc(as: ^atomspace.AtomSpace, h: atom.Handle) -> []atom.Handle {
    neighbors := make([dynamic]atom.Handle, context.temp_allocator)
    
    // Get incoming links
    incoming := atomspace.get_incoming(as, h)
    
    for link_h in incoming {
        link := atomspace.get_atom(as, link_h)
        if link != nil && atom.atom_is_link(link) {
            // Get other atoms in the link
            outgoing := link.outgoing
            for out_h in outgoing {
                if !atom.handle_equals(out_h, h) {
                    append(&neighbors, out_h)
                }
            }
        }
    }
    
    return neighbors[:]
}

// =============================================================================
// STIGMERGY TICK
// =============================================================================

// Main stigmergy tick
stigmergy_tick :: proc(sm: ^StigmergyManager) {
    sm.tick_count += 1
    
    // Decay traces
    stigmergy_decay(sm)
    
    // Diffuse traces periodically
    if sm.tick_count % 10 == 0 {
        stigmergy_diffuse(sm)
    }
    
    // Update statistics
    sm.stats.active_traces = 0
    for _, layer in sm.layers {
        sm.stats.active_traces += layer.active_count
    }
}

// =============================================================================
// PHEROMONE PATTERNS
// =============================================================================

// Create attention pheromone trail
stigmergy_attention_trail :: proc(
    sm: ^StigmergyManager,
    atoms: []atom.Handle,
    base_intensity: f64 = 1.0,
) {
    // Leave decreasing intensity along the trail
    n := len(atoms)
    for i, h in atoms {
        intensity := base_intensity * (1.0 - f64(i) / f64(n) * 0.5)
        stigmergy_leave_trace(sm, .ATTENTION_PHEROMONE, h, intensity, "attention_trail")
    }
}

// Create success marker
stigmergy_mark_success :: proc(
    sm: ^StigmergyManager,
    target: atom.Handle,
    reward: f64,
) {
    trace := stigmergy_leave_trace(sm, .SUCCESS_MARKER, target, reward, "success")
    if trace != nil {
        trace.data["reward"] = reward
    }
}

// Create goal signal
stigmergy_signal_goal :: proc(
    sm: ^StigmergyManager,
    goal_atom: atom.Handle,
    priority: f64,
) {
    trace := stigmergy_leave_trace(sm, .GOAL_SIGNAL, goal_atom, priority, "goal")
    if trace != nil {
        trace.data["priority"] = priority
    }
}

// Create obstacle warning
stigmergy_warn_obstacle :: proc(
    sm: ^StigmergyManager,
    obstacle: atom.Handle,
    severity: f64,
) {
    trace := stigmergy_leave_trace(sm, .OBSTACLE_WARNING, obstacle, severity, "obstacle")
    if trace != nil {
        trace.data["severity"] = severity
        // Warnings decay slowly
        trace.decay_rate = 0.999
    }
}

// =============================================================================
// STATISTICS
// =============================================================================

// Get stigmergy statistics
stigmergy_get_stats :: proc(sm: ^StigmergyManager) -> StigmergyStats {
    return sm.stats
}

// Get layer statistics
stigmergy_get_layer_stats :: proc(
    sm: ^StigmergyManager,
    type: TraceType,
) -> (active_count: int, total_intensity: f64, ok: bool) {
    layer, exists := sm.layers[type]
    if !exists {
        return 0, 0, false
    }
    
    return layer.active_count, layer.total_intensity, true
}
