// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Tick Function
//
// This module provides the unified tick function that executes
// one complete cognitive cycle. It serves as a simpler alternative
// to the full CognitiveCycle when you want direct control.

package odincog_cognitive_cycle

import "core:mem"
import "core:time"

// Core imports
import "../../core/atom"
import "../../core/atomspace"

// System imports
import "../../attention/ecan"
import "../../agents"
import "../../reasoning/ure"

// AIGLA imports
import "../../arena/state"
import "../../arena/sensors"
import "../../active_inference/agent"
import "../../niche/construction"
import "../../niche/evolution"
import "../../niche/stigmergy"

// =============================================================================
// TICK CONTEXT
// =============================================================================

// TickContext holds all components needed for a single tick
TickContext :: struct {
    // Core
    atomspace:          ^atomspace.AtomSpace,
    
    // World state
    world_state:        ^state.WorldState,
    sensor_hub:         ^sensors.SensorHub,
    
    // Active inference
    ai_agent:           ^agent.ActiveInferenceAgent,
    
    // Existing systems
    ecan_manager:       ^ecan.ECANManager,
    scheduler:          ^agents.Scheduler,
    rule_engine:        ^ure.UnifiedRuleEngine,
    
    // Niche
    niche_constructor:  ^construction.NicheConstructor,
    coevolution:        ^evolution.CoevolutionTracker,
    stigmergy_manager:  ^stigmergy.StigmergyManager,
    
    // Config
    config:             TickConfig,
    
    // State
    tick_count:         u64,
}

// TickConfig controls tick behavior
TickConfig :: struct {
    // Phase enables
    observe:        bool,
    predict:        bool,
    infer:          bool,
    act:            bool,
    learn:          bool,
    attend:         bool,
    construct:      bool,
    
    // Integration
    run_ecan:       bool,
    run_agents:     bool,
    run_ure:        bool,
}

DEFAULT_TICK_CONFIG :: TickConfig{
    observe = true,
    predict = true,
    infer = true,
    act = true,
    learn = true,
    attend = true,
    construct = true,
    run_ecan = true,
    run_agents = true,
    run_ure = true,
}

// TickResult contains the outcome of a tick
TickResult :: struct {
    // Metrics
    free_energy:        f64,
    entropy:            f64,
    prediction_error:   f64,
    
    // Activity
    observations:       int,
    predictions:        int,
    actions:            int,
    inferences:         int,
    
    // Timing (nanoseconds)
    phase_times:        [7]i64,
    total_time:         i64,
    
    // Status
    success:            bool,
    error:              string,
}

// =============================================================================
// UNIFIED TICK FUNCTION
// =============================================================================

// cognitive_tick executes one complete cognitive cycle
//
// The tick consists of 7 phases:
// 1. OBSERVE  - Gather sensory input from environment
// 2. PREDICT  - Generate predictions from generative model
// 3. INFER    - Update beliefs by minimizing free energy
// 4. ACT      - Select and execute actions via policy
// 5. LEARN    - Update model parameters from experience
// 6. ATTEND   - Run ECAN attention dynamics
// 7. CONSTRUCT - Niche construction and maintenance
//
cognitive_tick :: proc(ctx: ^TickContext) -> TickResult {
    result := TickResult{success = true}
    total_start := time.tick_now()
    
    // Phase 1: OBSERVE
    if ctx.config.observe {
        start := time.tick_now()
        result.observations = tick_observe(ctx)
        result.phase_times[0] = time.tick_diff(start, time.tick_now())
    }
    
    // Phase 2: PREDICT
    if ctx.config.predict {
        start := time.tick_now()
        result.predictions = tick_predict(ctx)
        result.phase_times[1] = time.tick_diff(start, time.tick_now())
    }
    
    // Phase 3: INFER
    if ctx.config.infer {
        start := time.tick_now()
        result.free_energy, result.prediction_error = tick_infer(ctx)
        result.inferences += 1
        result.phase_times[2] = time.tick_diff(start, time.tick_now())
    }
    
    // Phase 4: ACT
    if ctx.config.act {
        start := time.tick_now()
        result.actions = tick_act(ctx)
        result.phase_times[3] = time.tick_diff(start, time.tick_now())
    }
    
    // Phase 5: LEARN
    if ctx.config.learn {
        start := time.tick_now()
        tick_learn(ctx)
        result.phase_times[4] = time.tick_diff(start, time.tick_now())
    }
    
    // Phase 6: ATTEND
    if ctx.config.attend {
        start := time.tick_now()
        tick_attend(ctx)
        result.phase_times[5] = time.tick_diff(start, time.tick_now())
    }
    
    // Phase 7: CONSTRUCT
    if ctx.config.construct {
        start := time.tick_now()
        tick_construct(ctx)
        result.phase_times[6] = time.tick_diff(start, time.tick_now())
    }
    
    // Finalize
    ctx.tick_count += 1
    result.total_time = time.tick_diff(total_start, time.tick_now())
    
    return result
}

// =============================================================================
// PHASE IMPLEMENTATIONS
// =============================================================================

// tick_observe gathers sensory input
tick_observe :: proc(ctx: ^TickContext) -> int {
    observations := 0
    
    // Begin tick on world state
    if ctx.world_state != nil {
        state.world_state_begin_tick(ctx.world_state)
    }
    
    // Gather observations from sensor hub
    if ctx.sensor_hub != nil {
        obs := sensors.sensor_hub_gather(ctx.sensor_hub)
        observations = len(obs.observations)
        
        // Pass to agent
        if ctx.ai_agent != nil {
            agent.active_inference_agent_observe(ctx.ai_agent, obs)
        }
    }
    
    return observations
}

// tick_predict generates predictions
tick_predict :: proc(ctx: ^TickContext) -> int {
    predictions := 0
    
    if ctx.ai_agent != nil {
        agent.active_inference_agent_predict(ctx.ai_agent)
        predictions = agent.active_inference_agent_prediction_count(ctx.ai_agent)
    }
    
    return predictions
}

// tick_infer updates beliefs
tick_infer :: proc(ctx: ^TickContext) -> (f64, f64) {
    if ctx.ai_agent == nil {
        return 0, 0
    }
    
    // Run inference
    agent.active_inference_agent_infer(ctx.ai_agent)
    
    // Get free energy and prediction error
    fe := agent.active_inference_agent_get_free_energy(ctx.ai_agent)
    pe := agent.active_inference_agent_get_prediction_error(ctx.ai_agent)
    
    return fe, pe
}

// tick_act selects and executes actions
tick_act :: proc(ctx: ^TickContext) -> int {
    actions := 0
    
    // Active inference action selection
    if ctx.ai_agent != nil {
        agent.active_inference_agent_act(ctx.ai_agent)
        actions += 1
    }
    
    // URE forward chaining
    if ctx.config.run_ure && ctx.rule_engine != nil {
        fired := ure.ure_forward_step(ctx.rule_engine)
        actions += fired
    }
    
    // Legacy agents
    if ctx.config.run_agents && ctx.scheduler != nil {
        agents.scheduler_step(ctx.scheduler)
        actions += 1
    }
    
    return actions
}

// tick_learn updates model parameters
tick_learn :: proc(ctx: ^TickContext) {
    if ctx.ai_agent != nil {
        agent.active_inference_agent_learn(ctx.ai_agent)
    }
}

// tick_attend runs attention dynamics
tick_attend :: proc(ctx: ^TickContext) {
    // ECAN attention
    if ctx.config.run_ecan && ctx.ecan_manager != nil {
        ecan.ecan_run_step(ctx.ecan_manager)
    }
    
    // Stigmergy traces
    if ctx.stigmergy_manager != nil {
        stigmergy.stigmergy_tick(ctx.stigmergy_manager)
    }
}

// tick_construct performs niche construction
tick_construct :: proc(ctx: ^TickContext) {
    // Detect and act on affordances
    if ctx.niche_constructor != nil {
        construction.niche_detect_affordances(ctx.niche_constructor)
        construction.niche_maintenance(ctx.niche_constructor)
    }
    
    // Track coevolution
    if ctx.coevolution != nil {
        evolution.coevolution_tick(ctx.coevolution)
    }
    
    // Commit world state changes
    if ctx.world_state != nil {
        state.world_state_end_tick(ctx.world_state)
    }
}

// =============================================================================
// SIMPLIFIED TICK FUNCTIONS
// =============================================================================

// simple_tick runs a minimal tick with just core components
simple_tick :: proc(
    as: ^atomspace.AtomSpace,
    ai: ^agent.ActiveInferenceAgent,
) -> f64 {
    if ai == nil {
        return 0
    }
    
    // Basic observe-predict-infer-act cycle
    agent.active_inference_agent_predict(ai)
    agent.active_inference_agent_infer(ai)
    agent.active_inference_agent_act(ai)
    
    return agent.active_inference_agent_get_free_energy(ai)
}

// active_inference_tick runs just active inference phases
active_inference_tick :: proc(ai: ^agent.ActiveInferenceAgent) -> f64 {
    if ai == nil {
        return 0
    }
    
    agent.active_inference_agent_predict(ai)
    agent.active_inference_agent_infer(ai)
    agent.active_inference_agent_act(ai)
    agent.active_inference_agent_learn(ai)
    
    return agent.active_inference_agent_get_free_energy(ai)
}

// =============================================================================
// TICK UTILITIES
// =============================================================================

// Create tick context from cognitive cycle
tick_context_from_cycle :: proc(cycle: ^CognitiveCycle) -> TickContext {
    return TickContext{
        atomspace = cycle.atomspace,
        world_state = cycle.world_state,
        sensor_hub = cycle.sensor_hub,
        ai_agent = cycle.ai_agent,
        ecan_manager = cycle.ecan_manager,
        scheduler = cycle.scheduler,
        rule_engine = cycle.rule_engine,
        niche_constructor = cycle.niche_constructor,
        coevolution = cycle.coevolution,
        stigmergy_manager = cycle.stigmergy_manager,
        config = DEFAULT_TICK_CONFIG,
        tick_count = cycle.tick_count,
    }
}

// Get total time across all phases
tick_result_total_phase_time :: proc(result: ^TickResult) -> i64 {
    total: i64 = 0
    for t in result.phase_times {
        total += t
    }
    return total
}

// Get phase name by index
tick_phase_name :: proc(phase: int) -> string {
    names := [?]string{
        "OBSERVE", "PREDICT", "INFER", "ACT", "LEARN", "ATTEND", "CONSTRUCT",
    }
    if phase >= 0 && phase < len(names) {
        return names[phase]
    }
    return "UNKNOWN"
}

// Format tick result as string
tick_result_format :: proc(result: ^TickResult) -> string {
    // Returns a simple summary
    if result.success {
        return "Tick OK"
    }
    return result.error
}
