// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Generative Model
//
// This module implements the generative model for active inference.
// The generative model encodes:
// - Prior beliefs about the world state
// - Transition dynamics (how state evolves)
// - Observation likelihood (how observations relate to state)

package odincog_generative_model

import "core:mem"
import "core:math"
import "core:time"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"
import "../../arena/state"
import "../../arena/sensors"
import "../../reasoning/ure"

// =============================================================================
// BELIEF STATE
// =============================================================================

// BeliefState represents the agent's beliefs about the world
BeliefState :: struct {
    // Probability distributions over hidden states
    state_beliefs:          map[atom.Handle]f64,
    
    // Type-level beliefs (aggregate beliefs about atom types)
    type_beliefs:           map[types.AtomType]f64,
    
    // Relation beliefs (beliefs about links)
    relation_beliefs:       map[types.AtomType]f64,
    
    // Attention beliefs (expected attention distribution)
    attention_beliefs:      AttentionBeliefs,
    
    // Goal beliefs (belief about goal achievement)
    goal_beliefs:           map[atom.Handle]f64,
    
    // Uncertainty (entropy of belief state)
    entropy:                f64,
    
    // Last update
    last_updated:           time.Time,
    tick:                   u64,
    
    allocator:              mem.Allocator,
}

// AttentionBeliefs captures expected attention dynamics
AttentionBeliefs :: struct {
    expected_focus_size:    f64,
    expected_total_sti:     f64,
    expected_avg_sti:       f64,
    sti_variance:           f64,
}

// Create belief state
belief_state_create :: proc(allocator := context.allocator) -> ^BeliefState {
    bs := new(BeliefState, allocator)
    bs.state_beliefs = make(map[atom.Handle]f64, allocator)
    bs.type_beliefs = make(map[types.AtomType]f64, allocator)
    bs.relation_beliefs = make(map[types.AtomType]f64, allocator)
    bs.goal_beliefs = make(map[atom.Handle]f64, allocator)
    bs.allocator = allocator
    
    // Initialize with flat priors
    belief_state_initialize_priors(bs)
    
    return bs
}

// Destroy belief state
belief_state_destroy :: proc(bs: ^BeliefState) {
    if bs == nil {
        return
    }
    delete(bs.state_beliefs)
    delete(bs.type_beliefs)
    delete(bs.relation_beliefs)
    delete(bs.goal_beliefs)
    free(bs, bs.allocator)
}

// Initialize with uniform priors
belief_state_initialize_priors :: proc(bs: ^BeliefState) {
    // Flat prior for common atom types
    common_types := [?]types.AtomType{
        .CONCEPT_NODE, .PREDICATE_NODE, .VARIABLE_NODE,
        .INHERITANCE_LINK, .EVALUATION_LINK, .AND_LINK, .OR_LINK,
    }
    
    prior := 1.0 / f64(len(common_types))
    for t in common_types {
        bs.type_beliefs[t] = prior
    }
    
    // Default attention beliefs
    bs.attention_beliefs = AttentionBeliefs{
        expected_focus_size = 10,
        expected_total_sti = 0,
        expected_avg_sti = 0,
        sti_variance = 100,
    }
}

// Compute entropy of belief state
belief_state_entropy :: proc(bs: ^BeliefState) -> f64 {
    entropy: f64 = 0
    
    // Entropy over type beliefs
    for _, p in bs.type_beliefs {
        if p > 0 {
            entropy -= p * math.ln(p)
        }
    }
    
    // Entropy over state beliefs
    for _, p in bs.state_beliefs {
        if p > 0 {
            entropy -= p * math.ln(p)
        }
    }
    
    bs.entropy = entropy
    return entropy
}

// =============================================================================
// GENERATIVE MODEL
// =============================================================================

// GenerativeModel encodes the agent's world model
GenerativeModel :: struct {
    // Current beliefs
    beliefs:                ^BeliefState,
    
    // Prior beliefs (initial/default)
    prior_beliefs:          ^BeliefState,
    
    // Transition model parameters
    transition_params:      TransitionParams,
    
    // Observation model parameters
    observation_params:     ObservationParams,
    
    // Rule-based dynamics via URE
    rule_base:              ^ure.RuleBase,
    
    // Reference to atomspace
    atomspace:              ^atomspace.AtomSpace,
    
    // Model parameters
    learning_rate:          f64,
    prior_weight:           f64,
    
    // Statistics
    predictions_made:       u64,
    updates_performed:      u64,
    
    allocator:              mem.Allocator,
}

// TransitionParams models state transitions
TransitionParams :: struct {
    // Transition probabilities for atom types
    type_transitions:       map[types.AtomType]map[types.AtomType]f64,
    
    // Expected change rates
    expected_add_rate:      f64,
    expected_remove_rate:   f64,
    expected_modify_rate:   f64,
    
    // Attention dynamics
    sti_decay_rate:         f64,
    sti_spreading_rate:     f64,
    
    // Inference dynamics
    inference_rate:         f64,
}

// ObservationParams models observation likelihood
ObservationParams :: struct {
    // Precision (inverse variance) for different observation types
    atomspace_precision:    f64,
    attention_precision:    f64,
    inference_precision:    f64,
    external_precision:     f64,
    
    // Noise parameters
    observation_noise:      f64,
}

// Default model configuration
DEFAULT_TRANSITION_PARAMS :: TransitionParams{
    expected_add_rate = 0.1,
    expected_remove_rate = 0.01,
    expected_modify_rate = 0.05,
    sti_decay_rate = 0.95,
    sti_spreading_rate = 0.1,
    inference_rate = 0.1,
}

DEFAULT_OBSERVATION_PARAMS :: ObservationParams{
    atomspace_precision = 1.0,
    attention_precision = 0.5,
    inference_precision = 0.5,
    external_precision = 0.3,
    observation_noise = 0.01,
}

// =============================================================================
// GENERATIVE MODEL LIFECYCLE
// =============================================================================

// Create generative model
generative_model_create :: proc(
    as: ^atomspace.AtomSpace,
    rb: ^ure.RuleBase = nil,
    allocator := context.allocator,
) -> ^GenerativeModel {
    gm := new(GenerativeModel, allocator)
    
    gm.beliefs = belief_state_create(allocator)
    gm.prior_beliefs = belief_state_create(allocator)
    gm.transition_params = DEFAULT_TRANSITION_PARAMS
    gm.observation_params = DEFAULT_OBSERVATION_PARAMS
    gm.rule_base = rb
    gm.atomspace = as
    gm.learning_rate = 0.1
    gm.prior_weight = 0.5
    gm.allocator = allocator
    
    // Initialize transition type map
    gm.transition_params.type_transitions = make(map[types.AtomType]map[types.AtomType]f64, allocator)
    
    return gm
}

// Destroy generative model
generative_model_destroy :: proc(gm: ^GenerativeModel) {
    if gm == nil {
        return
    }
    
    belief_state_destroy(gm.beliefs)
    belief_state_destroy(gm.prior_beliefs)
    
    for _, inner in gm.transition_params.type_transitions {
        delete(inner)
    }
    delete(gm.transition_params.type_transitions)
    
    free(gm, gm.allocator)
}

// =============================================================================
// PREDICTION
// =============================================================================

// PredictionVector holds model predictions
PredictionVector :: struct {
    // Expected observations
    expected_atom_count:    f64,
    expected_link_count:    f64,
    expected_node_count:    f64,
    expected_avg_sti:       f64,
    expected_focus_size:    f64,
    expected_total_sti:     f64,
    expected_inference_count: f64,
    
    // Expected deltas
    expected_atoms_added:   f64,
    expected_atoms_removed: f64,
    expected_tvs_changed:   f64,
    expected_avs_changed:   f64,
    
    // Predicted attention events
    expected_focus_entries: f64,
    expected_focus_exits:   f64,
    
    // Energy predictions
    predicted_free_energy:  f64,
    
    // Uncertainty
    prediction_variance:    f64,
    
    // Timestamp
    tick:                   u64,
}

// Generate predictions from the generative model
generative_model_predict :: proc(
    gm: ^GenerativeModel,
    ws: ^state.WorldState,
) -> PredictionVector {
    gm.predictions_made += 1
    
    pred := PredictionVector{
        tick = ws.tick + 1,  // Predict for next tick
    }
    
    // Get current state
    stats := atomspace.atomspace_stats(gm.atomspace)
    summary := ws.attention_summary
    
    // Predict atom counts (assume small growth)
    current_atoms := f64(stats.total_atoms)
    pred.expected_atom_count = current_atoms * (1.0 + gm.transition_params.expected_add_rate - gm.transition_params.expected_remove_rate)
    pred.expected_node_count = f64(stats.total_nodes) * (1.0 + gm.transition_params.expected_add_rate * 0.7)
    pred.expected_link_count = f64(stats.total_links) * (1.0 + gm.transition_params.expected_add_rate * 0.3)
    
    // Predict attention
    pred.expected_total_sti = f64(summary.total_sti) * gm.transition_params.sti_decay_rate
    pred.expected_focus_size = f64(summary.atoms_in_focus)
    if current_atoms > 0 {
        pred.expected_avg_sti = pred.expected_total_sti / current_atoms
    }
    
    // Predict deltas
    pred.expected_atoms_added = current_atoms * gm.transition_params.expected_add_rate
    pred.expected_atoms_removed = current_atoms * gm.transition_params.expected_remove_rate
    pred.expected_tvs_changed = current_atoms * gm.transition_params.expected_modify_rate
    pred.expected_avs_changed = current_atoms * gm.transition_params.sti_spreading_rate
    
    // Predict focus changes
    pred.expected_focus_entries = pred.expected_focus_size * 0.1
    pred.expected_focus_exits = pred.expected_focus_size * 0.1
    
    // Predict inference count based on rule base
    if gm.rule_base != nil {
        rules := ure.rulebase_get_rules(gm.rule_base)
        pred.expected_inference_count = f64(len(rules)) * gm.transition_params.inference_rate
    }
    
    // Compute prediction variance (uncertainty)
    pred.prediction_variance = gm.observation_params.observation_noise * current_atoms
    
    // Predict free energy (starts at prior entropy)
    pred.predicted_free_energy = gm.beliefs.entropy
    
    return pred
}

// Convert prediction to observation-compatible features
prediction_to_features :: proc(pred: ^PredictionVector) -> [16]f64 {
    features: [16]f64
    
    features[0] = pred.expected_atom_count
    features[1] = pred.expected_link_count
    features[2] = pred.expected_node_count
    features[3] = pred.expected_avg_sti
    features[4] = pred.expected_focus_size
    features[5] = pred.expected_total_sti
    features[6] = pred.expected_inference_count
    features[7] = pred.expected_atoms_added
    features[8] = pred.expected_atoms_removed
    features[9] = pred.expected_tvs_changed
    features[10] = pred.expected_avs_changed
    features[11] = pred.expected_focus_entries
    features[12] = pred.expected_focus_exits
    features[13] = pred.predicted_free_energy
    features[14] = 0  // Prediction error (filled in later)
    features[15] = 0  // Surprisal (filled in later)
    
    return features
}

// =============================================================================
// BELIEF UPDATE
// =============================================================================

// Update beliefs based on observations
generative_model_update_beliefs :: proc(
    gm: ^GenerativeModel,
    observations: ^sensors.ObservationVector,
) {
    gm.updates_performed += 1
    bs := gm.beliefs
    
    // Update time
    bs.last_updated = time.now()
    bs.tick = observations.tick
    
    // Update type beliefs based on observed counts
    total := observations.atom_count
    if total > 0 {
        // Count by type
        type_counts := make(map[types.AtomType]int, context.temp_allocator)
        
        it := atomspace.atomspace_iterator(gm.atomspace)
        for {
            a, _, ok := atomspace.atomspace_iterate(&it)
            if !ok { break }
            type_counts[a.atom_type] += 1
        }
        
        // Update beliefs with Bayesian update
        for t, count in type_counts {
            observed := f64(count) / total
            prior := bs.type_beliefs[t]
            
            // Simple learning rule
            bs.type_beliefs[t] = (1 - gm.learning_rate) * prior + gm.learning_rate * observed
        }
    }
    
    // Update attention beliefs
    bs.attention_beliefs.expected_focus_size = 
        (1 - gm.learning_rate) * bs.attention_beliefs.expected_focus_size +
        gm.learning_rate * observations.focus_size
    
    bs.attention_beliefs.expected_total_sti =
        (1 - gm.learning_rate) * bs.attention_beliefs.expected_total_sti +
        gm.learning_rate * observations.total_sti
    
    bs.attention_beliefs.expected_avg_sti =
        (1 - gm.learning_rate) * bs.attention_beliefs.expected_avg_sti +
        gm.learning_rate * observations.avg_sti
    
    // Recompute entropy
    belief_state_entropy(bs)
}

// =============================================================================
// TRANSITION DYNAMICS
// =============================================================================

// Predict state transition probabilities
generative_model_transition_probability :: proc(
    gm: ^GenerativeModel,
    current_state: ^state.WorldState,
) -> map[types.AtomType]f64 {
    probs := make(map[types.AtomType]f64, gm.allocator)
    
    // Use type beliefs as base transition probabilities
    for t, p in gm.beliefs.type_beliefs {
        probs[t] = p
    }
    
    return probs
}

// Sample predicted next state (for simulation)
generative_model_sample_transition :: proc(
    gm: ^GenerativeModel,
    ws: ^state.WorldState,
) -> PredictionVector {
    base_pred := generative_model_predict(gm, ws)
    
    // Add noise based on variance
    noise := gm.observation_params.observation_noise
    
    // Perturb predictions
    base_pred.expected_atom_count += random_gaussian(0, noise * base_pred.expected_atom_count)
    base_pred.expected_focus_size += random_gaussian(0, noise * 10)
    base_pred.expected_total_sti += random_gaussian(0, noise * 100)
    
    return base_pred
}

// =============================================================================
// OBSERVATION MODEL
// =============================================================================

// Compute observation likelihood P(o|s)
generative_model_observation_likelihood :: proc(
    gm: ^GenerativeModel,
    observations: ^sensors.ObservationVector,
    predicted: PredictionVector,
) -> f64 {
    // Compute Gaussian likelihood
    obs_features := sensors.observation_vector_to_features(observations)
    pred_features := prediction_to_features(&predicted)
    
    log_likelihood: f64 = 0
    
    for i := 0; i < len(obs_features); i += 1 {
        diff := obs_features[i] - pred_features[i]
        precision := gm.observation_params.atomspace_precision
        
        // Different precision for different feature types
        if i >= 3 && i <= 6 {  // Attention features
            precision = gm.observation_params.attention_precision
        } else if i == 6 {  // Inference count
            precision = gm.observation_params.inference_precision
        }
        
        // Gaussian log likelihood
        log_likelihood -= 0.5 * precision * diff * diff
    }
    
    return math.exp(log_likelihood)
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

// Simple random Gaussian (Box-Muller transform)
random_gaussian :: proc(mean: f64, std: f64) -> f64 {
    // Use Odin's time as seed for basic randomness
    t := u64(time.now()._nsec)
    u1 := f64(t % 1000000) / 1000000.0 + 0.0001
    u2 := f64((t / 1000000) % 1000000) / 1000000.0 + 0.0001
    
    z := math.sqrt(-2 * math.ln(u1)) * math.cos(2 * math.PI * u2)
    return mean + std * z
}

// Get model statistics
GenerativeModelStats :: struct {
    predictions_made:       u64,
    updates_performed:      u64,
    belief_entropy:         f64,
    num_type_beliefs:       int,
    num_state_beliefs:      int,
}

generative_model_stats :: proc(gm: ^GenerativeModel) -> GenerativeModelStats {
    return GenerativeModelStats{
        predictions_made = gm.predictions_made,
        updates_performed = gm.updates_performed,
        belief_entropy = gm.beliefs.entropy,
        num_type_beliefs = len(gm.beliefs.type_beliefs),
        num_state_beliefs = len(gm.beliefs.state_beliefs),
    }
}
