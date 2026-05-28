// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Active Inference Agent
//
// This module implements the main active inference agent that integrates:
// - Generative model for world prediction
// - Free energy minimization for perception and action
// - Policy selection for goal-directed behavior

package odincog_active_agent

import "core:mem"
import "core:time"
import "core:fmt"
import "../model"
import "../inference"
import "../../arena/loop"
import "../../arena/state"
import "../../arena/sensors"
import "../../core/atom"
import "../../core/atomspace"
import "../../reasoning/ure"

// =============================================================================
// ACTIVE INFERENCE AGENT
// =============================================================================

// AgentConfig holds agent configuration
AgentConfig :: struct {
    // Learning parameters
    perception_learning_rate:   f64,
    action_learning_rate:       f64,
    precision_learning_rate:    f64,
    
    // Inference parameters
    perception_iterations:      int,
    policy_horizon:             int,
    
    // Precision parameters
    initial_sensory_precision:  f64,
    initial_policy_precision:   f64,
    
    // Exploration parameters
    exploration_bonus:          f64,
    curiosity_weight:           f64,
}

DEFAULT_AGENT_CONFIG :: AgentConfig{
    perception_learning_rate = 0.1,
    action_learning_rate = 0.05,
    precision_learning_rate = 0.01,
    perception_iterations = 5,
    policy_horizon = 3,
    initial_sensory_precision = 1.0,
    initial_policy_precision = 1.0,
    exploration_bonus = 0.1,
    curiosity_weight = 0.3,
}

// ActiveInferenceAgent is the main agent structure
ActiveInferenceAgent :: struct {
    // Configuration
    config:             AgentConfig,
    
    // Core components
    world_model:        ^model.GenerativeModel,
    preferences:        ^inference.PreferenceModel,
    
    // Current state
    beliefs:            ^model.BeliefState,
    observations:       ^sensors.ObservationVector,
    predictions:        model.PredictionVector,
    prediction_errors:  [16]f64,
    
    // Precision state
    precision:          inference.PrecisionState,
    
    // Policy state
    policy_prior:       ^ure.RuleBase,
    current_policy:     inference.PolicyOption,
    available_policies: [dynamic]inference.PolicyOption,
    
    // Energy state
    free_energy:        inference.FreeEnergyComponents,
    expected_free_energy: inference.ExpectedFreeEnergy,
    
    // History for learning
    fe_history:         [dynamic]f64,
    pe_history:         [dynamic]f64,
    action_history:     [dynamic]ActionRecord,
    
    // References
    atomspace:          ^atomspace.AtomSpace,
    world_state:        ^state.WorldState,
    sensor_manager:     ^sensors.SensorManager,
    
    // Statistics
    stats:              AgentStats,
    
    allocator:          mem.Allocator,
}

// ActionRecord logs executed actions
ActionRecord :: struct {
    tick:               u64,
    timestamp:          time.Time,
    policy:             inference.PolicyOption,
    expected_fe:        f64,
    actual_fe:          f64,
    success:            bool,
}

// AgentStats tracks agent performance
AgentStats :: struct {
    total_ticks:        u64,
    total_actions:      u64,
    successful_actions: u64,
    
    // Average metrics
    avg_free_energy:    f64,
    avg_prediction_error: f64,
    avg_entropy:        f64,
    
    // Cumulative metrics
    total_surprise:     f64,
    total_info_gain:    f64,
}

// =============================================================================
// AGENT LIFECYCLE
// =============================================================================

// Create active inference agent
active_agent_create :: proc(
    as: ^atomspace.AtomSpace,
    ws: ^state.WorldState,
    rb: ^ure.RuleBase = nil,
    config: AgentConfig = DEFAULT_AGENT_CONFIG,
    allocator := context.allocator,
) -> ^ActiveInferenceAgent {
    agent := new(ActiveInferenceAgent, allocator)
    
    agent.config = config
    agent.atomspace = as
    agent.world_state = ws
    agent.allocator = allocator
    
    // Create core components
    agent.world_model = model.generative_model_create(as, rb, allocator)
    agent.preferences = inference.preference_model_create(allocator)
    agent.beliefs = model.belief_state_create(allocator)
    agent.observations = sensors.observation_vector_create(allocator)
    
    // Initialize precision
    agent.precision = inference.PrecisionState{
        sensory_precision = config.initial_sensory_precision,
        policy_precision = config.initial_policy_precision,
        prior_precision = 1.0,
    }
    
    // Initialize policy structures
    agent.policy_prior = rb
    agent.available_policies = make([dynamic]inference.PolicyOption, allocator)
    
    // Initialize histories
    agent.fe_history = make([dynamic]f64, allocator)
    agent.pe_history = make([dynamic]f64, allocator)
    agent.action_history = make([dynamic]ActionRecord, allocator)
    
    // Create sensor manager
    agent.sensor_manager = sensors.sensor_manager_create(ws, allocator)
    
    // Generate initial policies from rule base
    if rb != nil {
        active_agent_generate_policies(agent)
    }
    
    return agent
}

// Destroy active inference agent
active_agent_destroy :: proc(agent: ^ActiveInferenceAgent) {
    if agent == nil {
        return
    }
    
    model.generative_model_destroy(agent.world_model)
    inference.preference_model_destroy(agent.preferences)
    model.belief_state_destroy(agent.beliefs)
    sensors.observation_vector_destroy(agent.observations)
    sensors.sensor_manager_destroy(agent.sensor_manager)
    
    delete(agent.available_policies)
    delete(agent.fe_history)
    delete(agent.pe_history)
    delete(agent.action_history)
    
    free(agent, agent.allocator)
}

// =============================================================================
// COGNITIVE CYCLE
// =============================================================================

// Run one cognitive tick
active_agent_tick :: proc(agent: ^ActiveInferenceAgent, dt: time.Duration) -> bool {
    agent.stats.total_ticks += 1
    
    // 1. OBSERVE - Gather sensory input
    active_agent_observe(agent)
    
    // 2. PREDICT - Generate predictions from model
    active_agent_predict(agent)
    
    // 3. INFER - Update beliefs (minimize free energy)
    active_agent_infer(agent)
    
    // 4. ACT - Select and execute policy
    active_agent_act(agent)
    
    // 5. LEARN - Update model parameters
    active_agent_learn(agent)
    
    return true
}

// Observation phase: gather sensory input
active_agent_observe :: proc(agent: ^ActiveInferenceAgent) {
    // Run all sensors
    obs := sensors.sensor_manager_observe(agent.sensor_manager)
    
    // Copy observations
    agent.observations^ = obs^
    
    // Compute surprisal
    surprisal := sensors.compute_surprisal(obs)
    agent.stats.total_surprise += surprisal
}

// Prediction phase: generate predictions from model
active_agent_predict :: proc(agent: ^ActiveInferenceAgent) {
    // Generate predictions from current beliefs
    agent.predictions = model.generative_model_predict(
        agent.world_model,
        agent.world_state,
    )
    
    // Compute prediction errors
    obs_features := sensors.observation_vector_to_features(agent.observations)
    pred_features := model.prediction_to_features(&agent.predictions)
    
    for i := 0; i < 16; i += 1 {
        agent.prediction_errors[i] = obs_features[i] - pred_features[i]
    }
}

// Inference phase: update beliefs to minimize free energy
active_agent_infer :: proc(agent: ^ActiveInferenceAgent) {
    // Perceptual inference: update beliefs based on observations
    agent.free_energy = inference.minimize_free_energy_perception(
        agent.world_model,
        agent.observations,
        agent.config.perception_iterations,
        agent.config.perception_learning_rate,
    )
    
    // Update statistics
    append(&agent.fe_history, agent.free_energy.total_free_energy)
    append(&agent.pe_history, agent.free_energy.prediction_error)
    
    // Keep history bounded
    max_history := 1000
    if len(agent.fe_history) > max_history {
        remove_range(&agent.fe_history, 0, len(agent.fe_history) - max_history)
    }
    if len(agent.pe_history) > max_history {
        remove_range(&agent.pe_history, 0, len(agent.pe_history) - max_history)
    }
    
    // Update running averages
    n := f64(agent.stats.total_ticks)
    agent.stats.avg_free_energy = ((n - 1) * agent.stats.avg_free_energy + agent.free_energy.total_free_energy) / n
    agent.stats.avg_prediction_error = ((n - 1) * agent.stats.avg_prediction_error + agent.free_energy.prediction_error) / n
    agent.stats.avg_entropy = ((n - 1) * agent.stats.avg_entropy + agent.free_energy.entropy) / n
}

// Action phase: select and execute policy
active_agent_act :: proc(agent: ^ActiveInferenceAgent) {
    // Update available policies
    if len(agent.available_policies) == 0 {
        active_agent_generate_policies(agent)
    }
    
    if len(agent.available_policies) == 0 {
        return  // No policies available
    }
    
    // Select action to minimize expected free energy
    best_policy, best_efe := inference.select_action_minimize_efe(
        agent.world_model,
        agent.available_policies[:],
        agent.preferences,
        agent.config.policy_horizon,
    )
    
    agent.current_policy = best_policy
    agent.expected_free_energy = inference.ExpectedFreeEnergy{total = best_efe}
    
    // Execute policy (apply rules)
    success := active_agent_execute_policy(agent, best_policy)
    
    // Record action
    record := ActionRecord{
        tick = agent.world_state.tick,
        timestamp = time.now(),
        policy = best_policy,
        expected_fe = best_efe,
        actual_fe = agent.free_energy.total_free_energy,
        success = success,
    }
    append(&agent.action_history, record)
    
    // Update stats
    agent.stats.total_actions += 1
    if success {
        agent.stats.successful_actions += 1
    }
}

// Execute a policy (apply rules from URE)
active_agent_execute_policy :: proc(agent: ^ActiveInferenceAgent, policy: inference.PolicyOption) -> bool {
    if agent.policy_prior == nil {
        return false
    }
    
    // Get rules from policy
    rules := ure.rulebase_get_rules(agent.policy_prior)
    
    // Apply selected rules
    for idx in policy.rule_indices {
        if idx >= 0 && idx < len(rules) {
            // Rule application would happen here via URE
            // This is a simplified version
        }
    }
    
    return true
}

// Learning phase: update model parameters
active_agent_learn :: proc(agent: ^ActiveInferenceAgent) {
    // Update generative model based on observations
    model.generative_model_update_beliefs(
        agent.world_model,
        agent.observations,
    )
    
    // Update precision based on prediction error history
    if len(agent.pe_history) > 10 {
        recent_pe := agent.pe_history[len(agent.pe_history)-10:]
        inference.update_precision(
            &agent.precision,
            recent_pe,
            agent.config.precision_learning_rate,
        )
    }
    
    // Update policy weights based on outcomes
    active_agent_update_policy_weights(agent)
    
    // Compute information gain
    if len(agent.fe_history) > 1 {
        prev_fe := agent.fe_history[len(agent.fe_history)-2]
        curr_fe := agent.fe_history[len(agent.fe_history)-1]
        info_gain := prev_fe - curr_fe
        if info_gain > 0 {
            agent.stats.total_info_gain += info_gain
        }
    }
}

// Update policy weights based on outcomes
active_agent_update_policy_weights :: proc(agent: ^ActiveInferenceAgent) {
    if len(agent.action_history) == 0 {
        return
    }
    
    // Get recent action
    recent := agent.action_history[len(agent.action_history)-1]
    
    // Compute outcome (how well did the action match expectations)
    outcome_error := recent.actual_fe - recent.expected_fe
    
    // Update policy priority based on outcome
    for &policy in agent.available_policies {
        if policy.name == recent.policy.name {
            // Decrease priority if outcome was worse than expected
            policy.priority -= agent.config.action_learning_rate * outcome_error
            
            // Clamp priority
            policy.priority = clamp(policy.priority, 0.1, 10.0)
        }
    }
}

// =============================================================================
// POLICY GENERATION
// =============================================================================

// Generate policies from rule base
active_agent_generate_policies :: proc(agent: ^ActiveInferenceAgent) {
    clear(&agent.available_policies)
    
    if agent.policy_prior == nil {
        // Generate default policies
        append(&agent.available_policies, inference.PolicyOption{
            name = "idle",
            rule_indices = nil,
            priority = 0.5,
            estimated_cost = 0.1,
        })
        return
    }
    
    rules := ure.rulebase_get_rules(agent.policy_prior)
    
    // Create single-rule policies
    for i := 0; i < len(rules); i += 1 {
        rule := rules[i]
        indices := make([]int, 1, agent.allocator)
        indices[0] = i
        
        append(&agent.available_policies, inference.PolicyOption{
            name = rule.name,
            rule_indices = indices,
            priority = rule.weight,
            estimated_cost = rule.cost,
        })
    }
    
    // Create compound policies (pairs of rules)
    for i := 0; i < len(rules); i += 1 {
        for j := i + 1; j < len(rules); j += 1 {
            if len(agent.available_policies) > 50 {
                break  // Limit total policies
            }
            
            indices := make([]int, 2, agent.allocator)
            indices[0] = i
            indices[1] = j
            
            append(&agent.available_policies, inference.PolicyOption{
                name = fmt.aprintf("%s+%s", rules[i].name, rules[j].name, allocator = agent.allocator),
                rule_indices = indices,
                priority = (rules[i].weight + rules[j].weight) / 2,
                estimated_cost = rules[i].cost + rules[j].cost,
            })
        }
    }
    
    // Add null policy (do nothing)
    append(&agent.available_policies, inference.PolicyOption{
        name = "null",
        rule_indices = nil,
        priority = 0.1,
        estimated_cost = 0,
    })
}

// =============================================================================
// GOAL MANAGEMENT
// =============================================================================

// Add a goal to the agent
active_agent_add_goal :: proc(agent: ^ActiveInferenceAgent, goal: inference.GoalSpec) {
    inference.preference_model_add_goal(agent.preferences, goal)
}

// Check if goals are satisfied
active_agent_check_goals :: proc(agent: ^ActiveInferenceAgent) -> []bool {
    if agent.preferences.goal_atoms == nil {
        return nil
    }
    
    results := make([]bool, len(agent.preferences.goal_atoms), context.temp_allocator)
    
    obs := agent.observations
    
    for i, goal in agent.preferences.goal_atoms {
        // Check if goal conditions are met
        satisfied := true
        
        if goal.target_atoms > 0 {
            satisfied = satisfied && obs.atom_count >= goal.target_atoms
        }
        if goal.target_focus > 0 {
            satisfied = satisfied && obs.focus_size >= goal.target_focus
        }
        if goal.target_sti > 0 {
            satisfied = satisfied && obs.total_sti >= goal.target_sti
        }
        
        results[i] = satisfied
    }
    
    return results
}

// =============================================================================
// CURIOSITY AND EXPLORATION
// =============================================================================

// Compute curiosity bonus for a state
active_agent_curiosity_bonus :: proc(agent: ^ActiveInferenceAgent, h: atom.Handle) -> f64 {
    // Curiosity is inversely related to belief confidence
    if confidence, ok := agent.beliefs.state_beliefs[h]; ok {
        // Low confidence = high curiosity
        return agent.config.curiosity_weight * (1.0 - confidence)
    }
    
    // Unknown atoms have maximum curiosity
    return agent.config.curiosity_weight
}

// Get epistemic actions (actions that reduce uncertainty)
active_agent_epistemic_actions :: proc(agent: ^ActiveInferenceAgent) -> []inference.PolicyOption {
    epistemic := make([dynamic]inference.PolicyOption, context.temp_allocator)
    
    for policy in agent.available_policies {
        // Simulate policy to estimate epistemic value
        predictions := inference.simulate_policy(
            agent.world_model,
            policy,
            agent.config.policy_horizon,
        )
        
        efe := inference.compute_expected_free_energy(
            agent.world_model,
            predictions,
            agent.preferences,
        )
        
        // Select policies with high epistemic value
        if efe.epistemic < -0.1 {  // Negative = information-seeking
            append(&epistemic, policy)
        }
    }
    
    return epistemic[:]
}

// =============================================================================
// STATISTICS AND DEBUGGING
// =============================================================================

// Get agent statistics
active_agent_get_stats :: proc(agent: ^ActiveInferenceAgent) -> AgentStats {
    return agent.stats
}

// Get current free energy
active_agent_get_free_energy :: proc(agent: ^ActiveInferenceAgent) -> f64 {
    return agent.free_energy.total_free_energy
}

// Get current prediction error
active_agent_get_prediction_error :: proc(agent: ^ActiveInferenceAgent) -> f64 {
    return agent.free_energy.prediction_error
}

// Get belief entropy
active_agent_get_entropy :: proc(agent: ^ActiveInferenceAgent) -> f64 {
    return agent.free_energy.entropy
}

// Format agent state as string
active_agent_to_string :: proc(agent: ^ActiveInferenceAgent, allocator := context.allocator) -> string {
    return fmt.aprintf(
        "ActiveInferenceAgent:\n" +
        "  Ticks: %d, Actions: %d/%d successful\n" +
        "  Free Energy: %.4f (avg: %.4f)\n" +
        "  Prediction Error: %.4f (avg: %.4f)\n" +
        "  Entropy: %.4f (avg: %.4f)\n" +
        "  Total Surprise: %.4f\n" +
        "  Total Info Gain: %.4f\n" +
        "  Available Policies: %d\n" +
        "  Current Policy: %s",
        agent.stats.total_ticks,
        agent.stats.successful_actions, agent.stats.total_actions,
        agent.free_energy.total_free_energy, agent.stats.avg_free_energy,
        agent.free_energy.prediction_error, agent.stats.avg_prediction_error,
        agent.free_energy.entropy, agent.stats.avg_entropy,
        agent.stats.total_surprise,
        agent.stats.total_info_gain,
        len(agent.available_policies),
        agent.current_policy.name,
        allocator = allocator,
    )
}
