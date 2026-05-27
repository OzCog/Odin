// OdinCog - OpenCog Implementation in Pure Odin
// Agent Framework
//
// This module implements the Mind Agent framework for cognitive processes.
// Agents are independent processes that operate on the AtomSpace, performing
// tasks like inference, attention allocation, and learning.

package odincog_agents

import "core:mem"
import "core:time"
import "core:sync"
import "core:thread"
import "core:fmt"
import "core:strings"
import "../../core/atomspace"

// =============================================================================
// AGENT INTERFACE
// =============================================================================

// AgentStatus represents the current state of an agent
AgentStatus :: enum {
    IDLE,           // Not running
    RUNNING,        // Currently executing
    PAUSED,         // Temporarily paused
    STOPPED,        // Permanently stopped
    ERROR,          // Error state
}

// AgentPriority for scheduling
AgentPriority :: enum {
    LOW,
    NORMAL,
    HIGH,
    CRITICAL,
}

// AgentInfo holds metadata about an agent
AgentInfo :: struct {
    name:           string,
    description:    string,
    priority:       AgentPriority,
    frequency:      time.Duration,  // How often to run
    last_run:       time.Time,
    total_runs:     u64,
    total_time:     time.Duration,
    status:         AgentStatus,
}

// Agent is the interface for all cognitive agents
Agent :: struct {
    // Agent identification and metadata
    info:           AgentInfo,
    
    // Reference to the AtomSpace
    atomspace:      ^atomspace.AtomSpace,
    
    // Agent-specific run function
    run_fn:         proc(agent: ^Agent) -> bool,
    
    // Optional initialization and cleanup
    init_fn:        proc(agent: ^Agent),
    cleanup_fn:     proc(agent: ^Agent),
    
    // User data for agent-specific state
    user_data:      rawptr,
    
    // Synchronization
    lock:           sync.Mutex,
    
    allocator:      mem.Allocator,
}

// Create a new agent
agent_create :: proc(
    name: string,
    description: string,
    as: ^atomspace.AtomSpace,
    run_fn: proc(agent: ^Agent) -> bool,
    priority: AgentPriority = .NORMAL,
    frequency: time.Duration = time.Millisecond * 100,
    allocator := context.allocator,
) -> ^Agent {
    agent := new(Agent, allocator)
    
    agent.info = AgentInfo{
        name = strings.clone(name, allocator),
        description = strings.clone(description, allocator),
        priority = priority,
        frequency = frequency,
        status = .IDLE,
    }
    
    agent.atomspace = as
    agent.run_fn = run_fn
    agent.allocator = allocator
    
    return agent
}

// Destroy an agent
agent_destroy :: proc(agent: ^Agent) {
    if agent == nil {
        return
    }
    
    // Run cleanup if defined
    if agent.cleanup_fn != nil {
        agent.cleanup_fn(agent)
    }
    
    delete(agent.info.name, agent.allocator)
    delete(agent.info.description, agent.allocator)
    free(agent, agent.allocator)
}

// Initialize an agent
agent_init :: proc(agent: ^Agent) {
    if agent.init_fn != nil {
        agent.init_fn(agent)
    }
    agent.info.status = .IDLE
}

// Run an agent once
agent_run_once :: proc(agent: ^Agent) -> bool {
    sync.guard(&agent.lock)
    
    if agent.info.status == .STOPPED {
        return false
    }
    
    agent.info.status = .RUNNING
    start := time.now()
    
    result := false
    if agent.run_fn != nil {
        result = agent.run_fn(agent)
    }
    
    elapsed := time.diff(start, time.now())
    agent.info.last_run = start
    agent.info.total_runs += 1
    agent.info.total_time += elapsed
    agent.info.status = .IDLE
    
    return result
}

// Pause an agent
agent_pause :: proc(agent: ^Agent) {
    sync.guard(&agent.lock)
    if agent.info.status == .RUNNING || agent.info.status == .IDLE {
        agent.info.status = .PAUSED
    }
}

// Resume an agent
agent_resume :: proc(agent: ^Agent) {
    sync.guard(&agent.lock)
    if agent.info.status == .PAUSED {
        agent.info.status = .IDLE
    }
}

// Stop an agent permanently
agent_stop :: proc(agent: ^Agent) {
    sync.guard(&agent.lock)
    agent.info.status = .STOPPED
}

// Check if agent should run based on frequency
agent_should_run :: proc(agent: ^Agent) -> bool {
    if agent.info.status != .IDLE {
        return false
    }
    
    elapsed := time.diff(agent.info.last_run, time.now())
    return elapsed >= agent.info.frequency
}

// =============================================================================
// AGENT SCHEDULER
// =============================================================================

// SchedulerConfig holds scheduler configuration
SchedulerConfig :: struct {
    // Maximum concurrent agents
    max_concurrent:     int,
    
    // Cycle time
    cycle_time:         time.Duration,
    
    // Priority weights
    priority_weights:   [AgentPriority]f64,
}

DEFAULT_SCHEDULER_CONFIG :: SchedulerConfig{
    max_concurrent = 4,
    cycle_time = time.Millisecond * 10,
    priority_weights = {
        .LOW = 0.5,
        .NORMAL = 1.0,
        .HIGH = 2.0,
        .CRITICAL = 4.0,
    },
}

// Scheduler manages agent execution
Scheduler :: struct {
    config:         SchedulerConfig,
    
    // Registered agents
    agents:         [dynamic]^Agent,
    
    // Thread pool for parallel execution
    pool:           ^thread.Pool,
    
    // Control
    running:        bool,
    cycle:          u64,
    
    // Synchronization
    lock:           sync.RW_Mutex,
    
    allocator:      mem.Allocator,
}

// Create a scheduler
scheduler_create :: proc(
    config: SchedulerConfig = DEFAULT_SCHEDULER_CONFIG,
    allocator := context.allocator,
) -> ^Scheduler {
    s := new(Scheduler, allocator)
    s.config = config
    s.agents = make([dynamic]^Agent, allocator)
    s.allocator = allocator
    
    // Initialize thread pool
    thread.pool_init(&s.pool, allocator, s.config.max_concurrent)
    
    return s
}

// Destroy a scheduler
scheduler_destroy :: proc(s: ^Scheduler) {
    if s == nil {
        return
    }
    
    scheduler_stop(s)
    
    // Don't destroy agents - they may be owned elsewhere
    delete(s.agents)
    
    thread.pool_destroy(s.pool)
    
    free(s, s.allocator)
}

// Register an agent with the scheduler
scheduler_register :: proc(s: ^Scheduler, agent: ^Agent) {
    sync.guard(&s.lock)
    append(&s.agents, agent)
}

// Unregister an agent
scheduler_unregister :: proc(s: ^Scheduler, agent: ^Agent) {
    sync.guard(&s.lock)
    
    for i := 0; i < len(s.agents); i += 1 {
        if s.agents[i] == agent {
            unordered_remove(&s.agents, i)
            return
        }
    }
}

// Start the scheduler (blocking)
scheduler_run :: proc(s: ^Scheduler) {
    s.running = true
    
    for s.running {
        s.cycle += 1
        
        // Run one scheduling cycle
        scheduler_run_cycle(s)
        
        // Sleep for cycle time
        time.sleep(s.config.cycle_time)
    }
}

// Run one scheduling cycle
scheduler_run_cycle :: proc(s: ^Scheduler) {
    sync.shared_guard(&s.lock)
    
    // Collect agents that should run
    agents_to_run := make([dynamic]^Agent, context.temp_allocator)
    
    for agent in s.agents {
        if agent_should_run(agent) {
            append(&agents_to_run, agent)
        }
    }
    
    // Sort by priority (higher priority first)
    scheduler_sort_by_priority(agents_to_run[:])
    
    // Run agents (respecting max_concurrent)
    for agent in agents_to_run {
        agent_run_once(agent)
    }
}

// Sort agents by priority (descending)
scheduler_sort_by_priority :: proc(agents: []^Agent) {
    // Simple insertion sort
    for i := 1; i < len(agents); i += 1 {
        j := i
        for j > 0 {
            if int(agents[j].info.priority) > int(agents[j-1].info.priority) {
                agents[j], agents[j-1] = agents[j-1], agents[j]
                j -= 1
            } else {
                break
            }
        }
    }
}

// Stop the scheduler
scheduler_stop :: proc(s: ^Scheduler) {
    s.running = false
}

// Get scheduler statistics
SchedulerStats :: struct {
    cycle:              u64,
    total_agents:       int,
    running_agents:     int,
    idle_agents:        int,
    paused_agents:      int,
}

scheduler_get_stats :: proc(s: ^Scheduler) -> SchedulerStats {
    sync.shared_guard(&s.lock)
    
    stats := SchedulerStats{
        cycle = s.cycle,
        total_agents = len(s.agents),
    }
    
    for agent in s.agents {
        switch agent.info.status {
            case .RUNNING:
                stats.running_agents += 1
            case .IDLE:
                stats.idle_agents += 1
            case .PAUSED:
                stats.paused_agents += 1
            case .STOPPED, .ERROR:
                // Not counted
        }
    }
    
    return stats
}

// =============================================================================
// BUILT-IN AGENTS
// =============================================================================

// Create an idle agent (does nothing, for testing)
create_idle_agent :: proc(as: ^atomspace.AtomSpace, allocator := context.allocator) -> ^Agent {
    return agent_create(
        "idle",
        "An idle agent that does nothing",
        as,
        proc(agent: ^Agent) -> bool {
            return true
        },
        .LOW,
        time.Second,
        allocator,
    )
}

// ImportanceUpdatingAgent state
ImportanceUpdatingState :: struct {
    update_count: int,
}

// Create an importance updating agent
create_importance_updating_agent :: proc(
    as: ^atomspace.AtomSpace,
    allocator := context.allocator,
) -> ^Agent {
    state := new(ImportanceUpdatingState, allocator)
    
    agent := agent_create(
        "importance-updating",
        "Updates importance values based on usage",
        as,
        proc(agent: ^Agent) -> bool {
            state := cast(^ImportanceUpdatingState)agent.user_data
            state.update_count += 1
            
            // Simple importance decay for all atoms
            it := atomspace.atomspace_iterator(agent.atomspace)
            for {
                a, _, ok := atomspace.atomspace_iterate(&it)
                if !ok {
                    break
                }
                
                // Decay STI slightly
                if a.attention_value.sti > 0 {
                    a.attention_value.sti -= 1
                } else if a.attention_value.sti < 0 {
                    a.attention_value.sti += 1
                }
            }
            
            return true
        },
        .NORMAL,
        time.Millisecond * 100,
        allocator,
    )
    
    agent.user_data = state
    
    agent.cleanup_fn = proc(agent: ^Agent) {
        if agent.user_data != nil {
            free(agent.user_data, agent.allocator)
        }
    }
    
    return agent
}
