// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Cognitive Cycle
//
// This module integrates all AIGLA components into a unified
// cognitive cycle. It connects:
// - Arena architecture (game loop, world state)
// - Active inference (agent, generative model)
// - Self-reflection (code mirror, meta-rules)
// - Niche construction (scaffolds, stigmergy)
// - Existing OdinCog systems (atomspace, ecan, ure)

package odincog_cognitive_cycle

import "core:mem"
import "core:time"
import "core:math"

// Core OdinCog imports
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"

// Existing systems
import "../../attention/ecan"
import "../../agents"
import "../../reasoning/ure"

// AIGLA imports
import "../../arena/loop"
import "../../arena/state"
import "../../arena/sensors"
import "../../arena/memory"

import "../../active_inference/agent"
import "../../active_inference/model"
import "../../active_inference/inference"
import "../../active_inference/policy"

import "../../meta/reflect"
import "../../meta/rules"
import "../../meta/patterns"

import "../../niche/construction"
import "../../niche/evolution"
import "../../niche/stigmergy"

// =============================================================================
// COGNITIVE CYCLE
// =============================================================================

// CognitiveCycle integrates all AIGLA components
CognitiveCycle :: struct {
    // Arena architecture
    game_loop:          ^loop.GameLoop,
    world_state:        ^state.WorldState,
    sensor_hub:         ^sensors.SensorHub,
    frame_arena:        ^memory.FrameArena,
    
    // Active inference
    ai_agent:           ^agent.ActiveInferenceAgent,
    
    // Existing OdinCog systems
    atomspace:          ^atomspace.AtomSpace,
    ecan_manager:       ^ecan.ECANManager,
    scheduler:          ^agents.Scheduler,
    rule_engine:        ^ure.UnifiedRuleEngine,
    
    // Self-reflection
    code_mirror:        ^reflect.CodeMirror,
    meta_rule_manager:  ^rules.MetaRuleManager,
    
    // Niche construction
    niche_constructor:  ^construction.NicheConstructor,
    coevolution:        ^evolution.CoevolutionTracker,
    stigmergy_manager:  ^stigmergy.StigmergyManager,
    
    // Metrics
    metrics:            CycleMetrics,
    
    // Configuration
    config:             CycleConfig,
    
    // State
    tick_count:         u64,
    is_running:         bool,
    
    allocator:          mem.Allocator,
}

// CycleMetrics tracks cognitive cycle performance
CycleMetrics :: struct {
    // Free energy
    free_energy:        f64,
    expected_free_energy: f64,
    
    // Complexity
    entropy:            f64,
    complexity:         f64,
    
    // Activity
    atoms_processed:    int,
    rules_fired:        int,
    inferences_made:    int,
    
    // Timing (nanoseconds)
    observe_time:       i64,
    predict_time:       i64,
    infer_time:         i64,
    act_time:           i64,
    learn_time:         i64,
    attend_time:        i64,
    construct_time:     i64,
    total_time:         i64,
    
    // Performance
    tick_rate:          f64,
    avg_tick_time:      f64,
}

// CycleConfig configures the cognitive cycle
CycleConfig :: struct {
    // Timing
    target_tick_rate:   f64,    // Target ticks per second
    max_tick_time:      f64,    // Maximum time per tick (seconds)
    
    // Phase enables
    enable_observe:     bool,
    enable_predict:     bool,
    enable_infer:       bool,
    enable_act:         bool,
    enable_learn:       bool,
    enable_attend:      bool,
    enable_construct:   bool,
    
    // Limits
    max_observations:   int,
    max_predictions:    int,
    max_actions:        int,
    max_constructions:  int,
    
    // Integration
    integrate_ecan:     bool,
    integrate_ure:      bool,
    integrate_agents:   bool,
    
    // Debug
    debug_mode:         bool,
    trace_enabled:      bool,
}

DEFAULT_CYCLE_CONFIG :: CycleConfig{
    target_tick_rate = 60.0,
    max_tick_time = 0.1,
    enable_observe = true,
    enable_predict = true,
    enable_infer = true,
    enable_act = true,
    enable_learn = true,
    enable_attend = true,
    enable_construct = true,
    max_observations = 1000,
    max_predictions = 100,
    max_actions = 10,
    max_constructions = 5,
    integrate_ecan = true,
    integrate_ure = true,
    integrate_agents = true,
    debug_mode = false,
    trace_enabled = false,
}

// =============================================================================
// LIFECYCLE
// =============================================================================

// Create cognitive cycle
cognitive_cycle_create :: proc(
    as: ^atomspace.AtomSpace,
    config: CycleConfig = DEFAULT_CYCLE_CONFIG,
    allocator := context.allocator,
) -> ^CognitiveCycle {
    cycle := new(CognitiveCycle, allocator)
    
    cycle.atomspace = as
    cycle.config = config
    cycle.allocator = allocator
    
    // Create frame arena
    cycle.frame_arena = memory.frame_arena_create(4 * 1024 * 1024, allocator)  // 4MB
    
    // Create world state
    cycle.world_state = state.world_state_create(as, allocator)
    
    // Create sensor hub
    cycle.sensor_hub = sensors.sensor_hub_create(as, cycle.world_state, allocator)
    
    // Create game loop (but don't start yet)
    loop_config := loop.DEFAULT_GAME_LOOP_CONFIG
    loop_config.target_fps = config.target_tick_rate
    cycle.game_loop = loop.game_loop_create(loop_config, allocator)
    
    // Create active inference agent
    agent_config := agent.DEFAULT_AGENT_CONFIG
    cycle.ai_agent = agent.active_inference_agent_create(as, nil, agent_config, allocator)
    
    // Create code mirror
    cycle.code_mirror = reflect.code_mirror_create(as, allocator)
    
    // Create meta-rule manager
    meta_config := rules.DEFAULT_META_RULE_CONFIG
    cycle.meta_rule_manager = rules.meta_rule_manager_create(nil, meta_config, allocator)
    
    // Create niche constructor
    niche_config := construction.DEFAULT_NICHE_CONFIG
    cycle.niche_constructor = construction.niche_constructor_create(cycle.world_state, niche_config, allocator)
    
    // Create coevolution tracker
    coevo_config := evolution.DEFAULT_COEVOLUTION_CONFIG
    cycle.coevolution = evolution.coevolution_tracker_create(cycle.world_state, cycle.niche_constructor, coevo_config, allocator)
    
    // Create stigmergy manager
    stig_config := stigmergy.DEFAULT_STIGMERGY_CONFIG
    cycle.stigmergy_manager = stigmergy.stigmergy_manager_create(cycle.world_state, stig_config, allocator)
    
    // Set up game loop callbacks
    setup_loop_callbacks(cycle)
    
    return cycle
}

// Destroy cognitive cycle
cognitive_cycle_destroy :: proc(cycle: ^CognitiveCycle) {
    if cycle == nil {
        return
    }
    
    // Stop if running
    if cycle.is_running {
        cognitive_cycle_stop(cycle)
    }
    
    // Destroy in reverse order
    stigmergy.stigmergy_manager_destroy(cycle.stigmergy_manager)
    evolution.coevolution_tracker_destroy(cycle.coevolution)
    construction.niche_constructor_destroy(cycle.niche_constructor)
    rules.meta_rule_manager_destroy(cycle.meta_rule_manager)
    reflect.code_mirror_destroy(cycle.code_mirror)
    agent.active_inference_agent_destroy(cycle.ai_agent)
    loop.game_loop_destroy(cycle.game_loop)
    sensors.sensor_hub_destroy(cycle.sensor_hub)
    state.world_state_destroy(cycle.world_state)
    memory.frame_arena_destroy(cycle.frame_arena)
    
    free(cycle, cycle.allocator)
}

// Set up game loop callbacks
setup_loop_callbacks :: proc(cycle: ^CognitiveCycle) {
    // Register tick callback for each phase
    loop.game_loop_set_tick_callback(cycle.game_loop, .OBSERVE, proc(gl: ^loop.GameLoop, ctx: rawptr) {
        cycle := cast(^CognitiveCycle)ctx
        if cycle.config.enable_observe {
            phase_observe(cycle)
        }
    }, cycle)
    
    loop.game_loop_set_tick_callback(cycle.game_loop, .PREDICT, proc(gl: ^loop.GameLoop, ctx: rawptr) {
        cycle := cast(^CognitiveCycle)ctx
        if cycle.config.enable_predict {
            phase_predict(cycle)
        }
    }, cycle)
    
    loop.game_loop_set_tick_callback(cycle.game_loop, .INFER, proc(gl: ^loop.GameLoop, ctx: rawptr) {
        cycle := cast(^CognitiveCycle)ctx
        if cycle.config.enable_infer {
            phase_infer(cycle)
        }
    }, cycle)
    
    loop.game_loop_set_tick_callback(cycle.game_loop, .ACT, proc(gl: ^loop.GameLoop, ctx: rawptr) {
        cycle := cast(^CognitiveCycle)ctx
        if cycle.config.enable_act {
            phase_act(cycle)
        }
    }, cycle)
    
    loop.game_loop_set_tick_callback(cycle.game_loop, .LEARN, proc(gl: ^loop.GameLoop, ctx: rawptr) {
        cycle := cast(^CognitiveCycle)ctx
        if cycle.config.enable_learn {
            phase_learn(cycle)
        }
    }, cycle)
    
    loop.game_loop_set_tick_callback(cycle.game_loop, .ATTEND, proc(gl: ^loop.GameLoop, ctx: rawptr) {
        cycle := cast(^CognitiveCycle)ctx
        if cycle.config.enable_attend {
            phase_attend(cycle)
        }
    }, cycle)
    
    loop.game_loop_set_tick_callback(cycle.game_loop, .CONSTRUCT, proc(gl: ^loop.GameLoop, ctx: rawptr) {
        cycle := cast(^CognitiveCycle)ctx
        if cycle.config.enable_construct {
            phase_construct(cycle)
        }
    }, cycle)
}

// =============================================================================
// CONTROL
// =============================================================================

// Start the cognitive cycle
cognitive_cycle_start :: proc(cycle: ^CognitiveCycle) {
    if cycle.is_running {
        return
    }
    
    cycle.is_running = true
    loop.game_loop_start(cycle.game_loop)
}

// Stop the cognitive cycle
cognitive_cycle_stop :: proc(cycle: ^CognitiveCycle) {
    if !cycle.is_running {
        return
    }
    
    cycle.is_running = false
    loop.game_loop_stop(cycle.game_loop)
}

// Pause the cognitive cycle
cognitive_cycle_pause :: proc(cycle: ^CognitiveCycle) {
    loop.game_loop_pause(cycle.game_loop)
}

// Resume the cognitive cycle
cognitive_cycle_resume :: proc(cycle: ^CognitiveCycle) {
    loop.game_loop_resume(cycle.game_loop)
}

// Step one tick
cognitive_cycle_step :: proc(cycle: ^CognitiveCycle) {
    loop.game_loop_step(cycle.game_loop)
}

// =============================================================================
// INTEGRATION WITH EXISTING SYSTEMS
// =============================================================================

// Set ECAN manager
cognitive_cycle_set_ecan :: proc(cycle: ^CognitiveCycle, ecan: ^ecan.ECANManager) {
    cycle.ecan_manager = ecan
}

// Set scheduler
cognitive_cycle_set_scheduler :: proc(cycle: ^CognitiveCycle, scheduler: ^agents.Scheduler) {
    cycle.scheduler = scheduler
}

// Set rule engine
cognitive_cycle_set_ure :: proc(cycle: ^CognitiveCycle, ure: ^ure.UnifiedRuleEngine) {
    cycle.rule_engine = ure
    
    // Also set in active inference agent for policy
    if cycle.ai_agent != nil {
        // Agent uses rule_base from URE
    }
}

// =============================================================================
// METRICS
// =============================================================================

// Get current metrics
cognitive_cycle_get_metrics :: proc(cycle: ^CognitiveCycle) -> CycleMetrics {
    return cycle.metrics
}

// Get tick count
cognitive_cycle_get_tick :: proc(cycle: ^CognitiveCycle) -> u64 {
    return cycle.tick_count
}

// Get free energy
cognitive_cycle_get_free_energy :: proc(cycle: ^CognitiveCycle) -> f64 {
    return cycle.metrics.free_energy
}

// =============================================================================
// PHASE IMPLEMENTATIONS
// =============================================================================

// OBSERVE phase - gather sensory input
phase_observe :: proc(cycle: ^CognitiveCycle) {
    start_time := time.tick_now()
    
    // Clear frame arena for this tick
    memory.frame_arena_reset(cycle.frame_arena)
    
    // Update world state
    state.world_state_begin_tick(cycle.world_state)
    
    // Gather observations from sensor hub
    observations := sensors.sensor_hub_gather(cycle.sensor_hub)
    
    // Pass observations to active inference agent
    if cycle.ai_agent != nil {
        agent.active_inference_agent_observe(cycle.ai_agent, observations)
    }
    
    cycle.metrics.observe_time = time.tick_diff(start_time, time.tick_now())
}

// PREDICT phase - generate predictions from model
phase_predict :: proc(cycle: ^CognitiveCycle) {
    start_time := time.tick_now()
    
    if cycle.ai_agent != nil {
        agent.active_inference_agent_predict(cycle.ai_agent)
    }
    
    cycle.metrics.predict_time = time.tick_diff(start_time, time.tick_now())
}

// INFER phase - update beliefs (minimize free energy)
phase_infer :: proc(cycle: ^CognitiveCycle) {
    start_time := time.tick_now()
    
    if cycle.ai_agent != nil {
        agent.active_inference_agent_infer(cycle.ai_agent)
        
        // Get free energy metrics
        cycle.metrics.free_energy = agent.active_inference_agent_get_free_energy(cycle.ai_agent)
    }
    
    cycle.metrics.infer_time = time.tick_diff(start_time, time.tick_now())
}

// ACT phase - select and execute policy
phase_act :: proc(cycle: ^CognitiveCycle) {
    start_time := time.tick_now()
    
    if cycle.ai_agent != nil {
        agent.active_inference_agent_act(cycle.ai_agent)
    }
    
    // Run legacy agents if integrated
    if cycle.config.integrate_agents && cycle.scheduler != nil {
        // Let scheduler run one step
        agents.scheduler_step(cycle.scheduler)
    }
    
    cycle.metrics.act_time = time.tick_diff(start_time, time.tick_now())
}

// LEARN phase - update model parameters
phase_learn :: proc(cycle: ^CognitiveCycle) {
    start_time := time.tick_now()
    
    if cycle.ai_agent != nil {
        agent.active_inference_agent_learn(cycle.ai_agent)
    }
    
    // Apply meta-rules for self-modification
    if cycle.meta_rule_manager != nil {
        rules.meta_rule_manager_tick(cycle.meta_rule_manager)
    }
    
    cycle.metrics.learn_time = time.tick_diff(start_time, time.tick_now())
}

// ATTEND phase - ECAN cycle
phase_attend :: proc(cycle: ^CognitiveCycle) {
    start_time := time.tick_now()
    
    if cycle.config.integrate_ecan && cycle.ecan_manager != nil {
        // Run ECAN update
        ecan.ecan_run_step(cycle.ecan_manager)
    }
    
    // Update stigmergic traces
    if cycle.stigmergy_manager != nil {
        stigmergy.stigmergy_tick(cycle.stigmergy_manager)
    }
    
    cycle.metrics.attend_time = time.tick_diff(start_time, time.tick_now())
}

// CONSTRUCT phase - niche construction
phase_construct :: proc(cycle: ^CognitiveCycle) {
    start_time := time.tick_now()
    
    // Detect affordances
    if cycle.niche_constructor != nil {
        construction.niche_detect_affordances(cycle.niche_constructor)
        construction.niche_maintenance(cycle.niche_constructor)
    }
    
    // Update coevolution tracking
    if cycle.coevolution != nil {
        evolution.coevolution_tick(cycle.coevolution)
    }
    
    // Commit world state changes
    state.world_state_end_tick(cycle.world_state)
    
    cycle.metrics.construct_time = time.tick_diff(start_time, time.tick_now())
    
    // Update total metrics
    cycle.tick_count += 1
    cycle.metrics.total_time = (
        cycle.metrics.observe_time +
        cycle.metrics.predict_time +
        cycle.metrics.infer_time +
        cycle.metrics.act_time +
        cycle.metrics.learn_time +
        cycle.metrics.attend_time +
        cycle.metrics.construct_time
    )
    
    // Compute tick rate
    cycle.metrics.avg_tick_time = f64(cycle.metrics.total_time) / 1_000_000_000.0
    if cycle.metrics.avg_tick_time > 0 {
        cycle.metrics.tick_rate = 1.0 / cycle.metrics.avg_tick_time
    }
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Load codebase into code mirror
cognitive_cycle_load_code :: proc(cycle: ^CognitiveCycle, source_dir: string) {
    if cycle.code_mirror != nil {
        reflect.code_mirror_load_directory(cycle.code_mirror, source_dir)
    }
}

// Create a checkpoint
cognitive_cycle_checkpoint :: proc(cycle: ^CognitiveCycle) -> ^state.StateCheckpoint {
    if cycle.world_state != nil {
        return state.world_state_checkpoint(cycle.world_state)
    }
    return nil
}

// Restore from checkpoint
cognitive_cycle_restore :: proc(cycle: ^CognitiveCycle, checkpoint: ^state.StateCheckpoint) -> bool {
    if cycle.world_state != nil {
        return state.world_state_restore(cycle.world_state, checkpoint)
    }
    return false
}

// Get coevolution fitness
cognitive_cycle_get_fitness :: proc(cycle: ^CognitiveCycle) -> f64 {
    if cycle.coevolution != nil {
        return evolution.coevolution_get_fitness(cycle.coevolution)
    }
    return 0
}

// Check if niche is stable
cognitive_cycle_is_stable :: proc(cycle: ^CognitiveCycle) -> bool {
    if cycle.coevolution != nil {
        stability := evolution.coevolution_get_stability(cycle.coevolution)
        return stability.is_stable
    }
    return true
}
