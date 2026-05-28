// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Goal System
//
// This module implements goal management where goals are represented
// as preferred observations (attractor states). It supports:
// - Goal hierarchy with priority inheritance
// - Subgoaling via backward chaining
// - Goal achievement detection
// - Goals as free energy minimization targets

package odincog_goal_system

import "core:mem"
import "core:time"
import "core:math"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"
import "../../active_inference/inference"

// =============================================================================
// GOAL TYPES
// =============================================================================

// GoalState indicates current goal status
GoalState :: enum {
    INACTIVE,       // Goal not being pursued
    PENDING,        // Goal awaiting activation
    ACTIVE,         // Goal currently being pursued
    SUSPENDED,      // Goal temporarily suspended
    ACHIEVED,       // Goal has been achieved
    FAILED,         // Goal has failed
    ABANDONED,      // Goal has been abandoned
}

// GoalType categorizes goals
GoalType :: enum {
    // Outcome goals
    ACHIEVE_STATE,      // Achieve a specific state
    MAINTAIN_STATE,     // Maintain a specific state
    AVOID_STATE,        // Avoid a specific state
    
    // Process goals
    EXPLORE,            // Explore/gather information
    LEARN,              // Learn a pattern or skill
    OPTIMIZE,           // Optimize some metric
    
    // Meta goals
    SUBGOAL,            // Instrumental subgoal
    CONDITIONAL,        // Conditional goal
    RECURRING,          // Recurring/periodic goal
}

// Goal represents a desired observation/state
Goal :: struct {
    // Identity
    id:                 u64,
    name:               string,
    type:               GoalType,
    
    // Target state (as atoms)
    target_atoms:       []atom.Handle,
    target_pattern:     ^PatternSpec,
    
    // As preferred observation (for active inference)
    preferred_obs:      ^inference.PreferenceModel,
    
    // Hierarchy
    parent:             ^Goal,
    children:           [dynamic]^Goal,
    
    // Priority
    base_priority:      f64,
    current_priority:   f64,
    urgency:            f64,
    importance:         f64,
    
    // State
    state:              GoalState,
    progress:           f64,        // 0-1 progress toward achievement
    
    // Temporal
    created_at:         time.Time,
    deadline:           Maybe(time.Time),
    last_progress:      time.Time,
    
    // Achievement
    achievement_threshold: f64,     // Progress level considered "achieved"
    failure_threshold:  f64,        // Progress below which goal fails
    
    // Context
    preconditions:      [dynamic]^Goal,
    postconditions:     [dynamic]atom.Handle,
    
    // Statistics
    attempts:           int,
    successes:          int,
    failures:           int,
    
    allocator:          mem.Allocator,
}

// PatternSpec describes a pattern to match
PatternSpec :: struct {
    pattern_type:       types.AtomType,
    variables:          []string,
    constraints:        []PatternConstraint,
}

// PatternConstraint limits pattern matching
PatternConstraint :: struct {
    variable:           string,
    constraint_type:    ConstraintType,
    value:              PatternValue,
}

// ConstraintType specifies constraint kind
ConstraintType :: enum {
    TYPE_IS,
    TYPE_NOT,
    TV_STRENGTH_GTE,
    TV_STRENGTH_LTE,
    TV_CONFIDENCE_GTE,
    HAS_INCOMING,
    HAS_OUTGOING,
}

// PatternValue holds constraint value
PatternValue :: union {
    types.AtomType,
    f64,
    int,
}

// =============================================================================
// GOAL SYSTEM
// =============================================================================

// GoalSystem manages all goals
GoalSystem :: struct {
    // Reference to atomspace
    atomspace:          ^atomspace.AtomSpace,
    
    // All goals
    goals:              [dynamic]^Goal,
    
    // Active goals (being pursued)
    active_goals:       [dynamic]^Goal,
    
    // Goal hierarchy roots
    root_goals:         [dynamic]^Goal,
    
    // Indexes
    goal_by_id:         map[u64]^Goal,
    goal_by_name:       map[string]^Goal,
    
    // Configuration
    config:             GoalConfig,
    
    // State
    next_id:            u64,
    tick_count:         u64,
    
    // Statistics
    stats:              GoalStats,
    
    allocator:          mem.Allocator,
}

// GoalConfig configures the goal system
GoalConfig :: struct {
    // Limits
    max_goals:              int,
    max_active_goals:       int,
    max_depth:              int,
    
    // Priority
    priority_decay:         f64,
    urgency_boost:          f64,
    
    // Achievement
    default_threshold:      f64,
    default_failure:        f64,
    
    // Subgoaling
    enable_subgoaling:      bool,
    max_subgoals:           int,
}

DEFAULT_GOAL_CONFIG :: GoalConfig{
    max_goals = 1000,
    max_active_goals = 10,
    max_depth = 5,
    priority_decay = 0.99,
    urgency_boost = 0.1,
    default_threshold = 0.9,
    default_failure = 0.1,
    enable_subgoaling = true,
    max_subgoals = 5,
}

// GoalStats tracks goal statistics
GoalStats :: struct {
    total_goals:        int,
    active_goals:       int,
    achieved_goals:     int,
    failed_goals:       int,
    avg_time_to_achieve: f64,
}

// =============================================================================
// LIFECYCLE
// =============================================================================

// Create goal system
goal_system_create :: proc(
    as: ^atomspace.AtomSpace,
    config: GoalConfig = DEFAULT_GOAL_CONFIG,
    allocator := context.allocator,
) -> ^GoalSystem {
    gs := new(GoalSystem, allocator)
    
    gs.atomspace = as
    gs.config = config
    gs.allocator = allocator
    gs.next_id = 1
    
    gs.goals = make([dynamic]^Goal, allocator)
    gs.active_goals = make([dynamic]^Goal, allocator)
    gs.root_goals = make([dynamic]^Goal, allocator)
    gs.goal_by_id = make(map[u64]^Goal, allocator)
    gs.goal_by_name = make(map[string]^Goal, allocator)
    
    return gs
}

// Destroy goal system
goal_system_destroy :: proc(gs: ^GoalSystem) {
    if gs == nil {
        return
    }
    
    for goal in gs.goals {
        goal_destroy(goal)
    }
    
    delete(gs.goals)
    delete(gs.active_goals)
    delete(gs.root_goals)
    delete(gs.goal_by_id)
    delete(gs.goal_by_name)
    
    free(gs, gs.allocator)
}

// =============================================================================
// GOAL CREATION
// =============================================================================

// Create a new goal
goal_create :: proc(
    gs: ^GoalSystem,
    name: string,
    type: GoalType,
    target_atoms: []atom.Handle,
    priority: f64 = 0.5,
) -> ^Goal {
    if len(gs.goals) >= gs.config.max_goals {
        return nil
    }
    
    goal := new(Goal, gs.allocator)
    
    goal.id = gs.next_id
    gs.next_id += 1
    
    goal.name = name
    goal.type = type
    goal.state = .INACTIVE
    goal.created_at = time.now()
    goal.allocator = gs.allocator
    
    // Copy target atoms
    if len(target_atoms) > 0 {
        goal.target_atoms = make([]atom.Handle, len(target_atoms), gs.allocator)
        copy(goal.target_atoms, target_atoms)
    }
    
    // Set priority
    goal.base_priority = priority
    goal.current_priority = priority
    goal.importance = priority
    
    // Set thresholds
    goal.achievement_threshold = gs.config.default_threshold
    goal.failure_threshold = gs.config.default_failure
    
    // Initialize collections
    goal.children = make([dynamic]^Goal, gs.allocator)
    goal.preconditions = make([dynamic]^Goal, gs.allocator)
    goal.postconditions = make([dynamic]atom.Handle, gs.allocator)
    
    // Register
    append(&gs.goals, goal)
    gs.goal_by_id[goal.id] = goal
    gs.goal_by_name[goal.name] = goal
    
    // Root goal if no parent
    append(&gs.root_goals, goal)
    
    gs.stats.total_goals += 1
    
    return goal
}

// Destroy a goal
goal_destroy :: proc(goal: ^Goal) {
    if goal == nil {
        return
    }
    
    delete(goal.target_atoms, goal.allocator)
    delete(goal.children)
    delete(goal.preconditions)
    delete(goal.postconditions)
    
    if goal.preferred_obs != nil {
        inference.preference_model_destroy(goal.preferred_obs)
    }
    
    free(goal, goal.allocator)
}

// =============================================================================
// GOAL HIERARCHY
// =============================================================================

// Add a subgoal
goal_add_subgoal :: proc(gs: ^GoalSystem, parent: ^Goal, child: ^Goal) {
    if parent == nil || child == nil {
        return
    }
    
    // Remove from root if it was there
    for i := 0; i < len(gs.root_goals); i += 1 {
        if gs.root_goals[i] == child {
            unordered_remove(&gs.root_goals, i)
            break
        }
    }
    
    // Add to parent
    child.parent = parent
    append(&parent.children, child)
    
    // Inherit some priority
    child.current_priority = max(child.base_priority, parent.current_priority * 0.8)
}

// Add a precondition
goal_add_precondition :: proc(goal: ^Goal, precondition: ^Goal) {
    if goal == nil || precondition == nil {
        return
    }
    
    append(&goal.preconditions, precondition)
}

// Check if all preconditions are met
goal_preconditions_met :: proc(goal: ^Goal) -> bool {
    for pre in goal.preconditions {
        if pre.state != .ACHIEVED {
            return false
        }
    }
    return true
}

// Get goal depth in hierarchy
goal_depth :: proc(goal: ^Goal) -> int {
    depth := 0
    current := goal.parent
    for current != nil {
        depth += 1
        current = current.parent
    }
    return depth
}

// =============================================================================
// GOAL STATE MANAGEMENT
// =============================================================================

// Activate a goal
goal_activate :: proc(gs: ^GoalSystem, goal: ^Goal) {
    if goal == nil || goal.state == .ACTIVE {
        return
    }
    
    // Check active limit
    if len(gs.active_goals) >= gs.config.max_active_goals {
        // Try to deactivate lowest priority
        if !try_deactivate_lowest(gs) {
            return
        }
    }
    
    // Check preconditions
    if !goal_preconditions_met(goal) {
        goal.state = .PENDING
        return
    }
    
    goal.state = .ACTIVE
    goal.attempts += 1
    append(&gs.active_goals, goal)
    gs.stats.active_goals += 1
}

// Deactivate a goal
goal_deactivate :: proc(gs: ^GoalSystem, goal: ^Goal) {
    if goal == nil || goal.state != .ACTIVE {
        return
    }
    
    goal.state = .SUSPENDED
    
    // Remove from active
    for i := 0; i < len(gs.active_goals); i += 1 {
        if gs.active_goals[i] == goal {
            unordered_remove(&gs.active_goals, i)
            gs.stats.active_goals -= 1
            break
        }
    }
}

// Try to deactivate lowest priority goal
try_deactivate_lowest :: proc(gs: ^GoalSystem) -> bool {
    if len(gs.active_goals) == 0 {
        return true
    }
    
    lowest: ^Goal = gs.active_goals[0]
    for goal in gs.active_goals {
        if goal.current_priority < lowest.current_priority {
            lowest = goal
        }
    }
    
    goal_deactivate(gs, lowest)
    return true
}

// Mark goal as achieved
goal_achieve :: proc(gs: ^GoalSystem, goal: ^Goal) {
    if goal == nil {
        return
    }
    
    goal.state = .ACHIEVED
    goal.progress = 1.0
    goal.successes += 1
    gs.stats.achieved_goals += 1
    
    // Remove from active
    for i := 0; i < len(gs.active_goals); i += 1 {
        if gs.active_goals[i] == goal {
            unordered_remove(&gs.active_goals, i)
            gs.stats.active_goals -= 1
            break
        }
    }
    
    // Propagate to parent
    if goal.parent != nil {
        update_parent_progress(goal.parent)
    }
    
    // Check waiting goals
    check_pending_goals(gs)
}

// Mark goal as failed
goal_fail :: proc(gs: ^GoalSystem, goal: ^Goal) {
    if goal == nil {
        return
    }
    
    goal.state = .FAILED
    goal.failures += 1
    gs.stats.failed_goals += 1
    
    // Remove from active
    for i := 0; i < len(gs.active_goals); i += 1 {
        if gs.active_goals[i] == goal {
            unordered_remove(&gs.active_goals, i)
            gs.stats.active_goals -= 1
            break
        }
    }
}

// Update progress
goal_update_progress :: proc(gs: ^GoalSystem, goal: ^Goal, progress: f64) {
    if goal == nil {
        return
    }
    
    old_progress := goal.progress
    goal.progress = clamp(progress, 0, 1)
    goal.last_progress = time.now()
    
    // Check achievement
    if goal.progress >= goal.achievement_threshold {
        goal_achieve(gs, goal)
    } else if goal.progress < goal.failure_threshold && old_progress >= goal.failure_threshold {
        // Progress dropped below failure threshold
        goal_fail(gs, goal)
    }
    
    // Update parent
    if goal.parent != nil {
        update_parent_progress(goal.parent)
    }
}

// Update parent progress based on children
update_parent_progress :: proc(parent: ^Goal) {
    if parent == nil || len(parent.children) == 0 {
        return
    }
    
    total_progress: f64 = 0
    for child in parent.children {
        total_progress += child.progress
    }
    
    parent.progress = total_progress / f64(len(parent.children))
}

// Check pending goals for activation
check_pending_goals :: proc(gs: ^GoalSystem) {
    for goal in gs.goals {
        if goal.state == .PENDING {
            if goal_preconditions_met(goal) {
                goal_activate(gs, goal)
            }
        }
    }
}

// =============================================================================
// GOAL SELECTION
// =============================================================================

// Get highest priority active goal
goal_system_top_goal :: proc(gs: ^GoalSystem) -> ^Goal {
    if len(gs.active_goals) == 0 {
        return nil
    }
    
    top: ^Goal = gs.active_goals[0]
    for goal in gs.active_goals {
        if goal.current_priority > top.current_priority {
            top = goal
        }
    }
    
    return top
}

// Select goals for this tick
goal_system_select_goals :: proc(gs: ^GoalSystem, n: int) -> []^Goal {
    if len(gs.active_goals) == 0 {
        return nil
    }
    
    // Sort by priority (simple selection for small n)
    result := make([dynamic]^Goal, gs.allocator)
    defer delete(result)
    
    taken := make([]bool, len(gs.active_goals), context.temp_allocator)
    
    for i := 0; i < min(n, len(gs.active_goals)); i += 1 {
        best_idx := -1
        best_priority: f64 = -1
        
        for j := 0; j < len(gs.active_goals); j += 1 {
            if !taken[j] && gs.active_goals[j].current_priority > best_priority {
                best_idx = j
                best_priority = gs.active_goals[j].current_priority
            }
        }
        
        if best_idx >= 0 {
            taken[best_idx] = true
            append(&result, gs.active_goals[best_idx])
        }
    }
    
    return result[:]
}

// =============================================================================
// GOAL ACHIEVEMENT DETECTION
// =============================================================================

// Check if goal target is achieved in atomspace
goal_check_achievement :: proc(gs: ^GoalSystem, goal: ^Goal) -> f64 {
    if goal == nil || len(goal.target_atoms) == 0 {
        return 0
    }
    
    // Check if all target atoms exist
    existing := 0
    for h in goal.target_atoms {
        if atomspace.get_atom(gs.atomspace, h) != nil {
            existing += 1
        }
    }
    
    if len(goal.target_atoms) > 0 {
        return f64(existing) / f64(len(goal.target_atoms))
    }
    
    return 0
}

// Check all active goals for achievement
goal_system_check_achievements :: proc(gs: ^GoalSystem) {
    for goal in gs.active_goals {
        progress := goal_check_achievement(gs, goal)
        goal_update_progress(gs, goal, progress)
    }
}

// =============================================================================
// SUBGOALING
// =============================================================================

// Create subgoal for a goal
goal_create_subgoal :: proc(
    gs: ^GoalSystem,
    parent: ^Goal,
    name: string,
    target_atoms: []atom.Handle,
) -> ^Goal {
    if parent == nil {
        return nil
    }
    
    // Check depth
    if goal_depth(parent) >= gs.config.max_depth {
        return nil
    }
    
    // Check subgoal limit
    if len(parent.children) >= gs.config.max_subgoals {
        return nil
    }
    
    subgoal := goal_create(
        gs,
        name,
        .SUBGOAL,
        target_atoms,
        parent.base_priority * 0.9,
    )
    
    if subgoal != nil {
        goal_add_subgoal(gs, parent, subgoal)
    }
    
    return subgoal
}

// =============================================================================
// GOAL SYSTEM TICK
// =============================================================================

// Run goal system tick
goal_system_tick :: proc(gs: ^GoalSystem) {
    gs.tick_count += 1
    
    // Update priorities (decay + urgency)
    for goal in gs.active_goals {
        // Decay priority
        goal.current_priority *= gs.config.priority_decay
        
        // Boost urgency if deadline approaching
        if deadline, has_deadline := goal.deadline.?; has_deadline {
            remaining := time.diff(time.now(), deadline)
            if remaining > 0 && remaining < time.Hour {
                goal.urgency = min(1.0, goal.urgency + gs.config.urgency_boost)
                goal.current_priority += goal.urgency * 0.1
            }
        }
    }
    
    // Check achievements
    goal_system_check_achievements(gs)
    
    // Activate pending goals
    check_pending_goals(gs)
}

// =============================================================================
// ACTIVE INFERENCE INTEGRATION
// =============================================================================

// Convert goal to preferred observation model
goal_to_preference :: proc(
    goal: ^Goal,
    allocator: mem.Allocator,
) -> ^inference.PreferenceModel {
    pref := inference.preference_model_create(allocator)
    
    // Target atoms become preferred observations
    for i, h in goal.target_atoms {
        // Create preference entry
        // The atom should exist with high truth value
        inference.preference_model_add(pref, h, 1.0, goal.importance)
    }
    
    return pref
}

// Get expected free energy reduction from achieving goal
goal_expected_fe_reduction :: proc(goal: ^Goal) -> f64 {
    if goal == nil {
        return 0
    }
    
    // Higher priority goals have higher expected FE reduction
    // Progress reduces remaining FE to minimize
    remaining := 1.0 - goal.progress
    return remaining * goal.current_priority * goal.importance
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Get goal by ID
goal_system_get :: proc(gs: ^GoalSystem, id: u64) -> ^Goal {
    return gs.goal_by_id[id]
}

// Get goal by name
goal_system_get_by_name :: proc(gs: ^GoalSystem, name: string) -> ^Goal {
    return gs.goal_by_name[name]
}

// Get all root goals
goal_system_roots :: proc(gs: ^GoalSystem) -> []^Goal {
    return gs.root_goals[:]
}

// Get statistics
goal_system_stats :: proc(gs: ^GoalSystem) -> GoalStats {
    return gs.stats
}

// Helper
clamp :: proc(x, lo, hi: f64) -> f64 {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}
