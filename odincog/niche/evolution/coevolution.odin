// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Coevolution Dynamics
//
// This module tracks agent-environment co-adaptation, representing the
// bidirectional influence between the agent and its environment (AtomSpace).
// Key concepts:
// - Fitness landscapes
// - Niche stability
// - Temporal dynamics

package odincog_coevolution

import "core:mem"
import "core:time"
import "core:math"
import "../../core/atom"
import "../../core/atomspace"
import "../../arena/state"
import "../construction"

// =============================================================================
// COEVOLUTION TYPES
// =============================================================================

// FitnessLandscape represents the agent's fitness surface
FitnessLandscape :: struct {
    // Dimensions of the landscape
    dimensions:         int,
    dimension_names:    []string,
    
    // Fitness values at sampled points
    samples:            [dynamic]FitnessSample,
    
    // Current position
    current_position:   []f64,
    current_fitness:    f64,
    
    // Gradient estimate
    gradient:           []f64,
    
    // History
    trajectory:         [dynamic][]f64,
    max_trajectory:     int,
    
    allocator:          mem.Allocator,
}

// FitnessSample is a point in the fitness landscape
FitnessSample :: struct {
    position:       []f64,
    fitness:        f64,
    timestamp:      time.Time,
}

// NicheStability measures how stable the agent's niche is
NicheStability :: struct {
    // Current stability metrics
    structural_stability:   f64,    // How stable is AtomSpace structure
    functional_stability:   f64,    // How stable are cognitive functions
    attention_stability:    f64,    // How stable is attention distribution
    
    // Volatility measures
    change_rate:            f64,    // Rate of environmental change
    adaptation_lag:         f64,    // How far behind is adaptation
    
    // Thresholds
    stability_threshold:    f64,    // Below this, niche is unstable
    crisis_threshold:       f64,    // Below this, niche is in crisis
    
    // State
    is_stable:              bool,
    is_in_crisis:           bool,
}

// TemporalDynamics tracks multi-scale temporal patterns
TemporalDynamics :: struct {
    // Short-term dynamics (ticks)
    short_term_window:      int,
    short_term_changes:     [dynamic]EnvironmentChange,
    
    // Medium-term dynamics (seconds/minutes)
    medium_term_window:     int,
    medium_term_patterns:   [dynamic]TemporalPattern,
    
    // Long-term dynamics (episodes)
    long_term_window:       int,
    long_term_trends:       [dynamic]Trend,
    
    // Time series
    fitness_series:         RingBuffer(f64),
    stability_series:       RingBuffer(f64),
    complexity_series:      RingBuffer(f64),
}

// EnvironmentChange represents a change in the environment
EnvironmentChange :: struct {
    tick:               u64,
    change_type:        ChangeType,
    magnitude:          f64,
    affected_atoms:     int,
    agent_caused:       bool,
}

// ChangeType categorizes environmental changes
ChangeType :: enum {
    ADDITION,           // New atoms added
    REMOVAL,            // Atoms removed
    MODIFICATION,       // Atoms modified
    REORGANIZATION,     // Structure changed
    ATTENTION_SHIFT,    // Attention redistributed
}

// TemporalPattern is a recurring temporal pattern
TemporalPattern :: struct {
    name:               string,
    period:             int,        // Period in ticks
    phase:              f64,        // Current phase
    amplitude:          f64,        // Pattern strength
    confidence:         f64,        // Detection confidence
}

// Trend represents a long-term trend
Trend :: struct {
    name:               string,
    direction:          TrendDirection,
    slope:              f64,
    r_squared:          f64,        // Goodness of fit
    start_time:         time.Time,
}

// TrendDirection indicates trend direction
TrendDirection :: enum {
    INCREASING,
    DECREASING,
    STABLE,
    OSCILLATING,
}

// RingBuffer for time series data
RingBuffer :: struct($T: typeid) {
    data:       []T,
    head:       int,
    count:      int,
    capacity:   int,
}

// =============================================================================
// COEVOLUTION TRACKER
// =============================================================================

// CoevolutionTracker monitors agent-environment co-adaptation
CoevolutionTracker :: struct {
    // References
    world_state:            ^state.WorldState,
    niche_constructor:      ^construction.NicheConstructor,
    
    // Fitness landscape
    landscape:              ^FitnessLandscape,
    
    // Stability tracking
    stability:              NicheStability,
    
    // Temporal dynamics
    dynamics:               TemporalDynamics,
    
    // Adaptation metrics
    adaptation_rate:        f64,
    niche_width:            f64,
    niche_overlap:          f64,
    
    // Configuration
    config:                 CoevolutionConfig,
    
    // State
    tick_count:             u64,
    last_update:            time.Time,
    
    allocator:              mem.Allocator,
}

// CoevolutionConfig holds configuration
CoevolutionConfig :: struct {
    // Landscape
    landscape_dimensions:   int,
    max_samples:            int,
    gradient_step:          f64,
    
    // Stability
    stability_threshold:    f64,
    crisis_threshold:       f64,
    stability_window:       int,
    
    // Temporal windows
    short_term_window:      int,
    medium_term_window:     int,
    long_term_window:       int,
    
    // Adaptation
    adaptation_rate_decay:  f64,
    min_adaptation_rate:    f64,
}

DEFAULT_COEVOLUTION_CONFIG :: CoevolutionConfig{
    landscape_dimensions = 5,
    max_samples = 1000,
    gradient_step = 0.01,
    stability_threshold = 0.5,
    crisis_threshold = 0.2,
    stability_window = 100,
    short_term_window = 60,
    medium_term_window = 600,
    long_term_window = 3600,
    adaptation_rate_decay = 0.999,
    min_adaptation_rate = 0.001,
}

// =============================================================================
// LIFECYCLE
// =============================================================================

// Create coevolution tracker
coevolution_tracker_create :: proc(
    ws: ^state.WorldState,
    nc: ^construction.NicheConstructor,
    config: CoevolutionConfig = DEFAULT_COEVOLUTION_CONFIG,
    allocator := context.allocator,
) -> ^CoevolutionTracker {
    ct := new(CoevolutionTracker, allocator)
    
    ct.world_state = ws
    ct.niche_constructor = nc
    ct.config = config
    ct.allocator = allocator
    ct.adaptation_rate = 1.0
    ct.last_update = time.now()
    
    // Create fitness landscape
    ct.landscape = fitness_landscape_create(config.landscape_dimensions, allocator)
    
    // Initialize stability
    ct.stability = NicheStability{
        stability_threshold = config.stability_threshold,
        crisis_threshold = config.crisis_threshold,
        is_stable = true,
    }
    
    // Initialize temporal dynamics
    ct.dynamics = TemporalDynamics{
        short_term_window = config.short_term_window,
        medium_term_window = config.medium_term_window,
        long_term_window = config.long_term_window,
        short_term_changes = make([dynamic]EnvironmentChange, allocator),
        medium_term_patterns = make([dynamic]TemporalPattern, allocator),
        long_term_trends = make([dynamic]Trend, allocator),
        fitness_series = ring_buffer_create(f64, 1000, allocator),
        stability_series = ring_buffer_create(f64, 1000, allocator),
        complexity_series = ring_buffer_create(f64, 1000, allocator),
    }
    
    return ct
}

// Destroy coevolution tracker
coevolution_tracker_destroy :: proc(ct: ^CoevolutionTracker) {
    if ct == nil {
        return
    }
    
    fitness_landscape_destroy(ct.landscape)
    
    delete(ct.dynamics.short_term_changes)
    delete(ct.dynamics.medium_term_patterns)
    delete(ct.dynamics.long_term_trends)
    ring_buffer_destroy(&ct.dynamics.fitness_series)
    ring_buffer_destroy(&ct.dynamics.stability_series)
    ring_buffer_destroy(&ct.dynamics.complexity_series)
    
    free(ct, ct.allocator)
}

// =============================================================================
// FITNESS LANDSCAPE
// =============================================================================

// Create fitness landscape
fitness_landscape_create :: proc(dimensions: int, allocator: mem.Allocator) -> ^FitnessLandscape {
    fl := new(FitnessLandscape, allocator)
    
    fl.dimensions = dimensions
    fl.dimension_names = make([]string, dimensions, allocator)
    fl.samples = make([dynamic]FitnessSample, allocator)
    fl.current_position = make([]f64, dimensions, allocator)
    fl.gradient = make([]f64, dimensions, allocator)
    fl.trajectory = make([dynamic][]f64, allocator)
    fl.max_trajectory = 100
    fl.allocator = allocator
    
    // Default dimension names
    default_names := [?]string{"complexity", "coherence", "flexibility", "efficiency", "novelty"}
    for i := 0; i < dimensions; i += 1 {
        if i < len(default_names) {
            fl.dimension_names[i] = default_names[i]
        } else {
            fl.dimension_names[i] = "dim"
        }
    }
    
    return fl
}

// Destroy fitness landscape
fitness_landscape_destroy :: proc(fl: ^FitnessLandscape) {
    if fl == nil {
        return
    }
    
    delete(fl.dimension_names, fl.allocator)
    for s in fl.samples {
        delete(s.position, fl.allocator)
    }
    delete(fl.samples)
    delete(fl.current_position, fl.allocator)
    delete(fl.gradient, fl.allocator)
    for t in fl.trajectory {
        delete(t, fl.allocator)
    }
    delete(fl.trajectory)
    
    free(fl, fl.allocator)
}

// Update fitness landscape with new sample
fitness_landscape_update :: proc(fl: ^FitnessLandscape, position: []f64, fitness: f64) {
    // Add sample
    sample := FitnessSample{
        position = make([]f64, len(position), fl.allocator),
        fitness = fitness,
        timestamp = time.now(),
    }
    copy(sample.position, position)
    
    append(&fl.samples, sample)
    
    // Update current position
    copy(fl.current_position, position)
    fl.current_fitness = fitness
    
    // Add to trajectory
    pos_copy := make([]f64, len(position), fl.allocator)
    copy(pos_copy, position)
    append(&fl.trajectory, pos_copy)
    
    // Prune old samples
    if len(fl.samples) > 1000 {
        delete(fl.samples[0].position, fl.allocator)
        ordered_remove(&fl.samples, 0)
    }
    
    // Prune trajectory
    if len(fl.trajectory) > fl.max_trajectory {
        delete(fl.trajectory[0], fl.allocator)
        ordered_remove(&fl.trajectory, 0)
    }
    
    // Estimate gradient
    estimate_gradient(fl)
}

// Estimate fitness gradient using nearby samples
estimate_gradient :: proc(fl: ^FitnessLandscape) {
    if len(fl.samples) < 2 {
        return
    }
    
    // Simple gradient estimate from recent samples
    for d := 0; d < fl.dimensions; d += 1 {
        fl.gradient[d] = 0
    }
    
    // Use last few samples
    window := min(10, len(fl.samples))
    
    for i := len(fl.samples) - window; i < len(fl.samples) - 1; i += 1 {
        s1 := fl.samples[i]
        s2 := fl.samples[i + 1]
        
        df := s2.fitness - s1.fitness
        
        for d := 0; d < fl.dimensions; d += 1 {
            dx := s2.position[d] - s1.position[d]
            if abs(dx) > 1e-10 {
                fl.gradient[d] += df / dx
            }
        }
    }
    
    // Average
    for d := 0; d < fl.dimensions; d += 1 {
        fl.gradient[d] /= f64(window - 1)
    }
}

// Get gradient ascent direction
fitness_landscape_ascent_direction :: proc(fl: ^FitnessLandscape) -> []f64 {
    // Normalize gradient
    magnitude: f64 = 0
    for d := 0; d < fl.dimensions; d += 1 {
        magnitude += fl.gradient[d] * fl.gradient[d]
    }
    magnitude = math.sqrt(magnitude)
    
    direction := make([]f64, fl.dimensions, fl.allocator)
    
    if magnitude > 1e-10 {
        for d := 0; d < fl.dimensions; d += 1 {
            direction[d] = fl.gradient[d] / magnitude
        }
    }
    
    return direction
}

// =============================================================================
// STABILITY TRACKING
// =============================================================================

// Update stability metrics
coevolution_update_stability :: proc(ct: ^CoevolutionTracker) {
    // Compute structural stability from AtomSpace changes
    if ct.world_state != nil {
        delta := ct.world_state.delta
        
        // Structural stability: low change rate = high stability
        total_changes := delta.added_count + delta.removed_count + delta.modified_count
        max_expected_changes: f64 = 100.0  // Normalize against expected maximum
        ct.stability.structural_stability = 1.0 - min(1.0, f64(total_changes) / max_expected_changes)
    }
    
    // Functional stability from niche constructions
    if ct.niche_constructor != nil {
        stats := construction.niche_get_stats(ct.niche_constructor)
        
        // More stable if scaffolds are being reused (not constantly rebuilt)
        if stats.active_scaffolds > 0 {
            ct.stability.functional_stability = min(1.0, f64(stats.active_scaffolds) * 0.1)
        }
    }
    
    // Attention stability from focus distribution
    if ct.world_state != nil {
        summary := ct.world_state.attention_summary
        
        // Entropy of attention distribution (higher = more stable)
        if summary.total_attention > 0 {
            ct.stability.attention_stability = min(1.0, summary.total_attention / 1000.0)
        }
    }
    
    // Compute overall change rate
    if len(ct.dynamics.short_term_changes) > 0 {
        total_magnitude: f64 = 0
        for change in ct.dynamics.short_term_changes {
            total_magnitude += change.magnitude
        }
        ct.stability.change_rate = total_magnitude / f64(len(ct.dynamics.short_term_changes))
    }
    
    // Determine stability state
    overall := (ct.stability.structural_stability + 
                ct.stability.functional_stability + 
                ct.stability.attention_stability) / 3.0
    
    ct.stability.is_stable = overall >= ct.stability.stability_threshold
    ct.stability.is_in_crisis = overall < ct.stability.crisis_threshold
}

// Record an environmental change
coevolution_record_change :: proc(
    ct: ^CoevolutionTracker,
    change_type: ChangeType,
    magnitude: f64,
    affected_atoms: int,
    agent_caused: bool,
) {
    change := EnvironmentChange{
        tick = ct.tick_count,
        change_type = change_type,
        magnitude = magnitude,
        affected_atoms = affected_atoms,
        agent_caused = agent_caused,
    }
    
    append(&ct.dynamics.short_term_changes, change)
    
    // Prune old changes
    if len(ct.dynamics.short_term_changes) > ct.config.short_term_window {
        ordered_remove(&ct.dynamics.short_term_changes, 0)
    }
}

// =============================================================================
// TEMPORAL DYNAMICS
// =============================================================================

// Update temporal dynamics
coevolution_update_dynamics :: proc(ct: ^CoevolutionTracker) {
    ct.tick_count += 1
    
    // Record time series
    ring_buffer_push(&ct.dynamics.fitness_series, ct.landscape.current_fitness)
    
    overall_stability := (ct.stability.structural_stability + 
                         ct.stability.functional_stability + 
                         ct.stability.attention_stability) / 3.0
    ring_buffer_push(&ct.dynamics.stability_series, overall_stability)
    
    // Compute complexity
    complexity: f64 = 0
    if ct.world_state != nil {
        stats := ct.world_state.atomspace_stats
        complexity = f64(stats.total_links) / max(1.0, f64(stats.total_nodes))
    }
    ring_buffer_push(&ct.dynamics.complexity_series, complexity)
    
    // Detect patterns periodically
    if ct.tick_count % 100 == 0 {
        detect_temporal_patterns(ct)
    }
    
    // Detect trends periodically
    if ct.tick_count % 1000 == 0 {
        detect_long_term_trends(ct)
    }
}

// Detect temporal patterns
detect_temporal_patterns :: proc(ct: ^CoevolutionTracker) {
    // Simple autocorrelation-based pattern detection
    // Look for periodic patterns in fitness series
    
    if ct.dynamics.fitness_series.count < 50 {
        return
    }
    
    // Test common periods
    periods := [?]int{10, 30, 60, 100}
    
    for period in periods {
        correlation := compute_autocorrelation(&ct.dynamics.fitness_series, period)
        
        if correlation > 0.5 {
            // Found a pattern
            pattern := TemporalPattern{
                name = "fitness_cycle",
                period = period,
                amplitude = correlation,
                confidence = correlation,
            }
            
            // Check if pattern already exists
            found := false
            for &p in ct.dynamics.medium_term_patterns {
                if p.period == period {
                    p.amplitude = correlation
                    p.confidence = (p.confidence + correlation) / 2
                    found = true
                    break
                }
            }
            
            if !found {
                append(&ct.dynamics.medium_term_patterns, pattern)
            }
        }
    }
}

// Compute autocorrelation for a given lag
compute_autocorrelation :: proc(rb: ^RingBuffer(f64), lag: int) -> f64 {
    if rb.count < lag + 10 {
        return 0
    }
    
    // Compute mean
    mean: f64 = 0
    for i := 0; i < rb.count; i += 1 {
        mean += ring_buffer_get(rb, i)
    }
    mean /= f64(rb.count)
    
    // Compute autocorrelation
    numerator: f64 = 0
    denominator: f64 = 0
    
    for i := 0; i < rb.count - lag; i += 1 {
        x1 := ring_buffer_get(rb, i) - mean
        x2 := ring_buffer_get(rb, i + lag) - mean
        numerator += x1 * x2
        denominator += x1 * x1
    }
    
    if denominator < 1e-10 {
        return 0
    }
    
    return numerator / denominator
}

// Detect long-term trends
detect_long_term_trends :: proc(ct: ^CoevolutionTracker) {
    // Simple linear regression for trend detection
    if ct.dynamics.fitness_series.count < 100 {
        return
    }
    
    // Compute fitness trend
    slope, r_squared := compute_linear_trend(&ct.dynamics.fitness_series)
    
    direction: TrendDirection
    if abs(slope) < 0.001 {
        direction = .STABLE
    } else if slope > 0 {
        direction = .INCREASING
    } else {
        direction = .DECREASING
    }
    
    trend := Trend{
        name = "fitness_trend",
        direction = direction,
        slope = slope,
        r_squared = r_squared,
        start_time = time.now(),
    }
    
    // Update or add trend
    found := false
    for &t in ct.dynamics.long_term_trends {
        if t.name == "fitness_trend" {
            t = trend
            found = true
            break
        }
    }
    
    if !found {
        append(&ct.dynamics.long_term_trends, trend)
    }
}

// Compute linear trend (slope, r_squared)
compute_linear_trend :: proc(rb: ^RingBuffer(f64)) -> (f64, f64) {
    if rb.count < 10 {
        return 0, 0
    }
    
    n := f64(rb.count)
    
    // Compute sums
    sum_x: f64 = 0
    sum_y: f64 = 0
    sum_xy: f64 = 0
    sum_x2: f64 = 0
    
    for i := 0; i < rb.count; i += 1 {
        x := f64(i)
        y := ring_buffer_get(rb, i)
        
        sum_x += x
        sum_y += y
        sum_xy += x * y
        sum_x2 += x * x
    }
    
    // Compute slope
    slope := (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
    
    // Compute r_squared
    mean_y := sum_y / n
    ss_tot: f64 = 0
    ss_res: f64 = 0
    
    for i := 0; i < rb.count; i += 1 {
        y := ring_buffer_get(rb, i)
        y_pred := slope * f64(i) + (mean_y - slope * f64(rb.count) / 2)
        
        ss_tot += (y - mean_y) * (y - mean_y)
        ss_res += (y - y_pred) * (y - y_pred)
    }
    
    r_squared: f64 = 1 - ss_res / max(ss_tot, 1e-10)
    
    return slope, r_squared
}

// =============================================================================
// RING BUFFER OPERATIONS
// =============================================================================

// Create ring buffer
ring_buffer_create :: proc($T: typeid, capacity: int, allocator: mem.Allocator) -> RingBuffer(T) {
    return RingBuffer(T){
        data = make([]T, capacity, allocator),
        head = 0,
        count = 0,
        capacity = capacity,
    }
}

// Destroy ring buffer
ring_buffer_destroy :: proc(rb: ^RingBuffer($T)) {
    delete(rb.data)
}

// Push to ring buffer
ring_buffer_push :: proc(rb: ^RingBuffer($T), value: T) {
    rb.data[rb.head] = value
    rb.head = (rb.head + 1) % rb.capacity
    rb.count = min(rb.count + 1, rb.capacity)
}

// Get from ring buffer (0 = oldest)
ring_buffer_get :: proc(rb: ^RingBuffer($T), index: int) -> T {
    if index < 0 || index >= rb.count {
        return T{}
    }
    
    actual_index := (rb.head - rb.count + index + rb.capacity) % rb.capacity
    return rb.data[actual_index]
}

// =============================================================================
// COEVOLUTION TICK
// =============================================================================

// Main coevolution update tick
coevolution_tick :: proc(ct: ^CoevolutionTracker) {
    // Update temporal dynamics
    coevolution_update_dynamics(ct)
    
    // Update stability
    coevolution_update_stability(ct)
    
    // Decay adaptation rate
    ct.adaptation_rate = max(
        ct.config.min_adaptation_rate,
        ct.adaptation_rate * ct.config.adaptation_rate_decay,
    )
    
    ct.last_update = time.now()
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Get overall fitness
coevolution_get_fitness :: proc(ct: ^CoevolutionTracker) -> f64 {
    return ct.landscape.current_fitness
}

// Get stability status
coevolution_get_stability :: proc(ct: ^CoevolutionTracker) -> NicheStability {
    return ct.stability
}

// Check if adaptation is needed
coevolution_needs_adaptation :: proc(ct: ^CoevolutionTracker) -> bool {
    return !ct.stability.is_stable || ct.stability.adaptation_lag > 0.5
}

// Get recommended adaptation magnitude
coevolution_adaptation_magnitude :: proc(ct: ^CoevolutionTracker) -> f64 {
    if ct.stability.is_in_crisis {
        return 1.0  // Large adaptation in crisis
    }
    
    if !ct.stability.is_stable {
        return 0.5  // Moderate adaptation if unstable
    }
    
    return ct.adaptation_rate  // Normal adaptation
}

// Get current trends
coevolution_get_trends :: proc(ct: ^CoevolutionTracker) -> []Trend {
    return ct.dynamics.long_term_trends[:]
}

// Get current patterns
coevolution_get_patterns :: proc(ct: ^CoevolutionTracker) -> []TemporalPattern {
    return ct.dynamics.medium_term_patterns[:]
}
