// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Game Loop Core
//
// This module implements a fixed timestep game loop that provides deterministic,
// tick-based execution for the cognitive architecture. The game loop follows
// the observe → predict → act → mutate cycle of active inference.

package odincog_game_loop

import "core:mem"
import "core:time"
import "core:sync"
import "core:fmt"

// =============================================================================
// GAME LOOP CONFIGURATION
// =============================================================================

// LoopConfig holds configuration for the game loop
LoopConfig :: struct {
    // Tick rate (Hz) - how many cognitive cycles per second
    tick_rate:              f64,
    
    // Fixed timestep duration (derived from tick_rate)
    fixed_timestep:         time.Duration,
    
    // Maximum accumulated time before dropping frames
    max_accumulator:        time.Duration,
    
    // Whether to use fixed timestep (vs variable)
    use_fixed_timestep:     bool,
    
    // Performance monitoring
    track_metrics:          bool,
    metrics_window:         int,  // Number of frames to average
}

// Default configuration: 60 cognitive cycles per second
DEFAULT_LOOP_CONFIG :: LoopConfig{
    tick_rate = 60.0,
    fixed_timestep = time.Duration(16_666_666),  // ~16.67ms
    max_accumulator = time.Duration(250_000_000), // 250ms
    use_fixed_timestep = true,
    track_metrics = true,
    metrics_window = 60,
}

// =============================================================================
// LOOP STATE
// =============================================================================

// LoopState represents the current state of the game loop
LoopState :: enum {
    STOPPED,
    RUNNING,
    PAUSED,
    STEPPING,     // Single-step mode for debugging
}

// LoopPhase indicates the current phase within a tick
LoopPhase :: enum {
    OBSERVE,      // Gather sensory input
    PREDICT,      // Generate predictions from model
    INFER,        // Update beliefs (minimize free energy)
    ACT,          // Select and execute policy
    LEARN,        // Update model parameters
    ATTEND,       // ECAN attention cycle
    CONSTRUCT,    // Niche construction
}

// LoopMetrics holds performance metrics
LoopMetrics :: struct {
    // Tick counters
    tick_count:             u64,
    total_ticks:            u64,
    
    // Timing
    last_tick_time:         time.Time,
    tick_duration:          time.Duration,
    avg_tick_duration:      time.Duration,
    max_tick_duration:      time.Duration,
    min_tick_duration:      time.Duration,
    
    // Frame timing
    frame_times:            [dynamic]time.Duration,
    frame_index:            int,
    
    // Phase timing
    phase_times:            [LoopPhase]time.Duration,
    
    // Performance
    ticks_per_second:       f64,
    cpu_utilization:        f64,
    
    // Accumulated time (for fixed timestep)
    accumulator:            time.Duration,
    interpolation:          f64,  // For rendering between ticks
}

// =============================================================================
// GAME LOOP STRUCTURE
// =============================================================================

// TickCallback is called each cognitive tick
TickCallback :: proc(loop: ^GameLoop, phase: LoopPhase, dt: time.Duration) -> bool

// GameLoop manages the cognitive cycle timing
GameLoop :: struct {
    // Configuration
    config:             LoopConfig,
    
    // State
    state:              LoopState,
    current_phase:      LoopPhase,
    
    // Metrics
    metrics:            LoopMetrics,
    
    // Callbacks for each phase
    callbacks:          [LoopPhase]TickCallback,
    
    // Generic tick callback (called for all phases)
    tick_callback:      proc(loop: ^GameLoop, dt: time.Duration) -> bool,
    
    // User data
    user_data:          rawptr,
    
    // Time tracking
    start_time:         time.Time,
    last_frame_time:    time.Time,
    
    // Control
    should_stop:        bool,
    steps_remaining:    int,  // For stepping mode
    
    // Synchronization
    lock:               sync.Mutex,
    
    allocator:          mem.Allocator,
}

// =============================================================================
// GAME LOOP LIFECYCLE
// =============================================================================

// Create a new game loop
game_loop_create :: proc(
    config: LoopConfig = DEFAULT_LOOP_CONFIG,
    allocator := context.allocator,
) -> ^GameLoop {
    loop := new(GameLoop, allocator)
    
    loop.config = config
    loop.state = .STOPPED
    loop.current_phase = .OBSERVE
    loop.allocator = allocator
    
    // Initialize metrics
    if config.track_metrics {
        loop.metrics.frame_times = make([dynamic]time.Duration, config.metrics_window, allocator)
        loop.metrics.min_tick_duration = time.Duration(max(i64))
    }
    
    // Calculate fixed timestep from tick rate
    if config.tick_rate > 0 {
        loop.config.fixed_timestep = time.Duration(i64(1_000_000_000.0 / config.tick_rate))
    }
    
    return loop
}

// Destroy a game loop
game_loop_destroy :: proc(loop: ^GameLoop) {
    if loop == nil {
        return
    }
    
    if loop.config.track_metrics {
        delete(loop.metrics.frame_times)
    }
    
    free(loop, loop.allocator)
}

// =============================================================================
// CALLBACK REGISTRATION
// =============================================================================

// Set callback for a specific phase
game_loop_set_phase_callback :: proc(loop: ^GameLoop, phase: LoopPhase, callback: TickCallback) {
    loop.callbacks[phase] = callback
}

// Set generic tick callback
game_loop_set_tick_callback :: proc(loop: ^GameLoop, callback: proc(^GameLoop, time.Duration) -> bool) {
    loop.tick_callback = callback
}

// =============================================================================
// GAME LOOP CONTROL
// =============================================================================

// Start the game loop (blocking)
game_loop_run :: proc(loop: ^GameLoop) {
    loop.state = .RUNNING
    loop.should_stop = false
    loop.start_time = time.now()
    loop.last_frame_time = loop.start_time
    loop.metrics.accumulator = 0
    
    for !loop.should_stop && loop.state != .STOPPED {
        game_loop_frame(loop)
        
        // Handle stepping mode
        if loop.state == .STEPPING {
            loop.steps_remaining -= 1
            if loop.steps_remaining <= 0 {
                loop.state = .PAUSED
            }
        }
    }
}

// Run a single frame of the game loop
game_loop_frame :: proc(loop: ^GameLoop) {
    current_time := time.now()
    frame_time := time.diff(loop.last_frame_time, current_time)
    loop.last_frame_time = current_time
    
    // Clamp frame time to prevent spiral of death
    if frame_time > loop.config.max_accumulator {
        frame_time = loop.config.max_accumulator
    }
    
    if loop.config.use_fixed_timestep {
        // Fixed timestep mode
        loop.metrics.accumulator += frame_time
        
        for loop.metrics.accumulator >= loop.config.fixed_timestep {
            game_loop_tick(loop, loop.config.fixed_timestep)
            loop.metrics.accumulator -= loop.config.fixed_timestep
        }
        
        // Calculate interpolation for rendering
        loop.metrics.interpolation = f64(loop.metrics.accumulator) / f64(loop.config.fixed_timestep)
    } else {
        // Variable timestep mode
        game_loop_tick(loop, frame_time)
    }
}

// Execute one cognitive tick
game_loop_tick :: proc(loop: ^GameLoop, dt: time.Duration) {
    if loop.state == .PAUSED {
        return
    }
    
    tick_start := time.now()
    loop.metrics.tick_count += 1
    loop.metrics.total_ticks += 1
    
    // Run through all phases
    phases := [?]LoopPhase{.OBSERVE, .PREDICT, .INFER, .ACT, .LEARN, .ATTEND, .CONSTRUCT}
    
    for phase in phases {
        loop.current_phase = phase
        phase_start := time.now()
        
        // Call phase-specific callback
        if loop.callbacks[phase] != nil {
            if !loop.callbacks[phase](loop, phase, dt) {
                loop.should_stop = true
                break
            }
        }
        
        // Track phase timing
        if loop.config.track_metrics {
            loop.metrics.phase_times[phase] = time.diff(phase_start, time.now())
        }
    }
    
    // Call generic tick callback if set
    if loop.tick_callback != nil {
        if !loop.tick_callback(loop, dt) {
            loop.should_stop = true
        }
    }
    
    // Update metrics
    if loop.config.track_metrics {
        tick_duration := time.diff(tick_start, time.now())
        loop.metrics.tick_duration = tick_duration
        loop.metrics.last_tick_time = tick_start
        
        // Update min/max
        if tick_duration < loop.metrics.min_tick_duration {
            loop.metrics.min_tick_duration = tick_duration
        }
        if tick_duration > loop.metrics.max_tick_duration {
            loop.metrics.max_tick_duration = tick_duration
        }
        
        // Update rolling average
        loop.metrics.frame_times[loop.metrics.frame_index] = tick_duration
        loop.metrics.frame_index = (loop.metrics.frame_index + 1) % loop.config.metrics_window
        
        // Calculate average
        total: time.Duration = 0
        for t in loop.metrics.frame_times {
            total += t
        }
        loop.metrics.avg_tick_duration = total / time.Duration(loop.config.metrics_window)
        
        // Calculate ticks per second
        if loop.metrics.avg_tick_duration > 0 {
            loop.metrics.ticks_per_second = 1_000_000_000.0 / f64(loop.metrics.avg_tick_duration)
        }
    }
}

// Stop the game loop
game_loop_stop :: proc(loop: ^GameLoop) {
    loop.should_stop = true
    loop.state = .STOPPED
}

// Pause the game loop
game_loop_pause :: proc(loop: ^GameLoop) {
    sync.guard(&loop.lock)
    if loop.state == .RUNNING {
        loop.state = .PAUSED
    }
}

// Resume the game loop
game_loop_resume :: proc(loop: ^GameLoop) {
    sync.guard(&loop.lock)
    if loop.state == .PAUSED {
        loop.state = .RUNNING
        loop.last_frame_time = time.now()  // Reset to avoid time jump
    }
}

// Step forward N ticks (for debugging)
game_loop_step :: proc(loop: ^GameLoop, steps: int = 1) {
    sync.guard(&loop.lock)
    loop.steps_remaining = steps
    loop.state = .STEPPING
}

// =============================================================================
// METRICS AND DEBUGGING
// =============================================================================

// Get current metrics
game_loop_get_metrics :: proc(loop: ^GameLoop) -> LoopMetrics {
    return loop.metrics
}

// Get current state
game_loop_get_state :: proc(loop: ^GameLoop) -> LoopState {
    return loop.state
}

// Get current phase
game_loop_get_phase :: proc(loop: ^GameLoop) -> LoopPhase {
    return loop.current_phase
}

// Get elapsed time since start
game_loop_get_elapsed :: proc(loop: ^GameLoop) -> time.Duration {
    return time.diff(loop.start_time, time.now())
}

// Get tick count
game_loop_get_tick_count :: proc(loop: ^GameLoop) -> u64 {
    return loop.metrics.total_ticks
}

// Reset metrics
game_loop_reset_metrics :: proc(loop: ^GameLoop) {
    loop.metrics.tick_count = 0
    loop.metrics.max_tick_duration = 0
    loop.metrics.min_tick_duration = time.Duration(max(i64))
    
    for &t in loop.metrics.frame_times {
        t = 0
    }
    loop.metrics.frame_index = 0
    
    for &t in loop.metrics.phase_times {
        t = 0
    }
}

// Format metrics as string
game_loop_metrics_string :: proc(loop: ^GameLoop, allocator := context.allocator) -> string {
    m := &loop.metrics
    
    return fmt.aprintf(
        "GameLoop Metrics:\n" +
        "  Ticks: %d (total: %d)\n" +
        "  TPS: %.2f\n" +
        "  Tick duration: avg=%.3fms, min=%.3fms, max=%.3fms\n" +
        "  Phase times: observe=%.3fms, predict=%.3fms, infer=%.3fms\n" +
        "               act=%.3fms, learn=%.3fms, attend=%.3fms, construct=%.3fms",
        m.tick_count, m.total_ticks,
        m.ticks_per_second,
        f64(m.avg_tick_duration) / 1_000_000.0,
        f64(m.min_tick_duration) / 1_000_000.0,
        f64(m.max_tick_duration) / 1_000_000.0,
        f64(m.phase_times[.OBSERVE]) / 1_000_000.0,
        f64(m.phase_times[.PREDICT]) / 1_000_000.0,
        f64(m.phase_times[.INFER]) / 1_000_000.0,
        f64(m.phase_times[.ACT]) / 1_000_000.0,
        f64(m.phase_times[.LEARN]) / 1_000_000.0,
        f64(m.phase_times[.ATTEND]) / 1_000_000.0,
        f64(m.phase_times[.CONSTRUCT]) / 1_000_000.0,
        allocator = allocator,
    )
}

// =============================================================================
// TIME UTILITIES
// =============================================================================

// Convert tick count to time
ticks_to_time :: proc(loop: ^GameLoop, ticks: u64) -> time.Duration {
    return time.Duration(i64(ticks)) * loop.config.fixed_timestep
}

// Convert time to tick count
time_to_ticks :: proc(loop: ^GameLoop, duration: time.Duration) -> u64 {
    if loop.config.fixed_timestep > 0 {
        return u64(duration / loop.config.fixed_timestep)
    }
    return 0
}

// Get interpolation factor for rendering between ticks
game_loop_get_interpolation :: proc(loop: ^GameLoop) -> f64 {
    return loop.metrics.interpolation
}
