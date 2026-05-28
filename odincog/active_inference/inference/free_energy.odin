// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Free Energy Minimization
//
// This module implements the core free energy calculations for active inference.
// Free energy is an upper bound on surprisal, and minimizing it leads to:
// - Perception: updating beliefs to match observations
// - Action: selecting actions to make observations match predictions

package odincog_free_energy

import "core:math"
import "core:mem"
import "../model"
import "../../arena/sensors"

// =============================================================================
// FREE ENERGY TYPES
// =============================================================================

// FreeEnergyComponents breaks down free energy into its components
FreeEnergyComponents :: struct {
    // Total variational free energy: F = E_q[ln q(s) - ln p(o,s)]
    total_free_energy:      f64,
    
    // Accuracy term: E_q[ln p(o|s)] (negative prediction error)
    accuracy:               f64,
    
    // Complexity term: D_KL[q(s) || p(s)] (divergence from prior)
    complexity:             f64,
    
    // Alternative decomposition:
    // Energy term: E_q[-ln p(o,s)]
    energy:                 f64,
    
    // Entropy term: H[q(s)]
    entropy:                f64,
    
    // Precision-weighted prediction error
    prediction_error:       f64,
    
    // State uncertainty
    state_uncertainty:      f64,
}

// ExpectedFreeEnergy for action/policy selection
ExpectedFreeEnergy :: struct {
    // Total expected free energy: G = E_q[ln q(s|pi) - ln p(o,s|pi)]
    total:                  f64,
    
    // Pragmatic value (expected utility)
    pragmatic:              f64,
    
    // Epistemic value (expected information gain)
    epistemic:              f64,
    
    // Risk (expected complexity)
    risk:                   f64,
    
    // Ambiguity (expected uncertainty)
    ambiguity:              f64,
}

// =============================================================================
// FREE ENERGY COMPUTATION
// =============================================================================

// Compute variational free energy
compute_free_energy :: proc(
    gm: ^model.GenerativeModel,
    observations: ^sensors.ObservationVector,
    predictions: model.PredictionVector,
) -> FreeEnergyComponents {
    fe := FreeEnergyComponents{}
    
    // Get feature vectors
    obs_features := sensors.observation_vector_to_features(observations)
    pred_features := model.prediction_to_features(&predictions)
    
    // Compute precision-weighted prediction error
    pe: f64 = 0
    for i := 0; i < len(obs_features); i += 1 {
        diff := obs_features[i] - pred_features[i]
        precision := get_feature_precision(gm, i)
        pe += precision * diff * diff
    }
    fe.prediction_error = pe / f64(len(obs_features))
    
    // Accuracy: negative prediction error (higher is better)
    fe.accuracy = -fe.prediction_error
    
    // Entropy of belief state
    fe.entropy = gm.beliefs.entropy
    
    // Complexity: KL divergence from prior
    fe.complexity = compute_kl_divergence(gm.beliefs, gm.prior_beliefs)
    
    // Energy: -ln p(o,s)
    likelihood := model.generative_model_observation_likelihood(gm, observations, predictions)
    if likelihood > 0 {
        fe.energy = -math.ln(likelihood)
    } else {
        fe.energy = 1000  // Large penalty for zero likelihood
    }
    
    // State uncertainty: variance of beliefs
    fe.state_uncertainty = compute_state_uncertainty(gm)
    
    // Total free energy: F = E - H = complexity + accuracy
    // Or equivalently: F = energy - entropy
    fe.total_free_energy = fe.energy - fe.entropy
    
    return fe
}

// Get precision for a specific feature index
get_feature_precision :: proc(gm: ^model.GenerativeModel, feature_idx: int) -> f64 {
    // Features 0-6: atomspace/attention features
    // Features 7-12: delta features
    // Features 13-15: energy features
    
    if feature_idx <= 2 {
        return gm.observation_params.atomspace_precision
    } else if feature_idx <= 6 {
        return gm.observation_params.attention_precision
    } else if feature_idx <= 12 {
        return gm.observation_params.atomspace_precision * 0.5
    } else {
        return gm.observation_params.inference_precision
    }
}

// Compute KL divergence between belief states
compute_kl_divergence :: proc(q: ^model.BeliefState, p: ^model.BeliefState) -> f64 {
    kl: f64 = 0
    
    // KL divergence over type beliefs
    for t, q_prob in q.type_beliefs {
        if p_prob, ok := p.type_beliefs[t]; ok {
            if q_prob > 0 && p_prob > 0 {
                kl += q_prob * math.ln(q_prob / p_prob)
            }
        }
    }
    
    return kl
}

// Compute state uncertainty from belief variances
compute_state_uncertainty :: proc(gm: ^model.GenerativeModel) -> f64 {
    // Approximate uncertainty as entropy
    return gm.beliefs.entropy
}

// =============================================================================
// EXPECTED FREE ENERGY (FOR ACTION SELECTION)
// =============================================================================

// Compute expected free energy for a policy
compute_expected_free_energy :: proc(
    gm: ^model.GenerativeModel,
    policy_predictions: []model.PredictionVector,
    preferences: ^PreferenceModel,
) -> ExpectedFreeEnergy {
    efe := ExpectedFreeEnergy{}
    
    // Sum over prediction horizon
    for pred in policy_predictions {
        // Pragmatic value: expected utility (closeness to preferences)
        efe.pragmatic += compute_pragmatic_value(pred, preferences)
        
        // Epistemic value: expected information gain
        efe.epistemic += compute_epistemic_value(gm, pred)
        
        // Risk: expected divergence from prior
        efe.risk += pred.prediction_variance
        
        // Ambiguity: expected observation uncertainty
        efe.ambiguity += pred.prediction_variance * 0.5
    }
    
    // Normalize by horizon length
    n := f64(len(policy_predictions))
    if n > 0 {
        efe.pragmatic /= n
        efe.epistemic /= n
        efe.risk /= n
        efe.ambiguity /= n
    }
    
    // Total EFE: pragmatic + epistemic (both negative = good)
    // Risk and ambiguity are penalties
    efe.total = efe.pragmatic + efe.epistemic + efe.risk + efe.ambiguity
    
    return efe
}

// =============================================================================
// PREFERENCE MODEL
// =============================================================================

// PreferenceModel encodes desired observations
PreferenceModel :: struct {
    // Preferred observation features
    preferred_observations: [16]f64,
    
    // Weights for each feature
    preference_weights:     [16]f64,
    
    // Goal atoms (preferred to be present/true)
    goal_atoms:             []GoalSpec,
    
    allocator:              mem.Allocator,
}

// GoalSpec specifies a goal state
GoalSpec :: struct {
    description:    string,
    importance:     f64,
    
    // Target observation values
    target_atoms:   f64,
    target_focus:   f64,
    target_sti:     f64,
    
    // Satisfaction threshold
    threshold:      f64,
}

// Create preference model
preference_model_create :: proc(allocator := context.allocator) -> ^PreferenceModel {
    pm := new(PreferenceModel, allocator)
    pm.allocator = allocator
    
    // Initialize with default preferences
    // Prefer stable atom count, moderate focus size, low free energy
    pm.preferred_observations = [16]f64{
        100,    // atom count
        50,     // link count
        50,     // node count
        10,     // avg STI
        20,     // focus size
        500,    // total STI
        5,      // inference count
        5,      // atoms added
        1,      // atoms removed
        5,      // TVs changed
        10,     // AVs changed
        2,      // focus entries
        2,      // focus exits
        0,      // free energy (prefer low)
        0,      // prediction error (prefer low)
        0,      // surprisal (prefer low)
    }
    
    // Equal weights by default
    for i := 0; i < 16; i += 1 {
        pm.preference_weights[i] = 1.0
    }
    
    // Higher weight on energy-related features
    pm.preference_weights[13] = 2.0  // free energy
    pm.preference_weights[14] = 2.0  // prediction error
    pm.preference_weights[15] = 2.0  // surprisal
    
    return pm
}

// Destroy preference model
preference_model_destroy :: proc(pm: ^PreferenceModel) {
    if pm == nil {
        return
    }
    if pm.goal_atoms != nil {
        delete(pm.goal_atoms, pm.allocator)
    }
    free(pm, pm.allocator)
}

// Add a goal to the preference model
preference_model_add_goal :: proc(pm: ^PreferenceModel, goal: GoalSpec) {
    if pm.goal_atoms == nil {
        pm.goal_atoms = make([]GoalSpec, 0, 8, pm.allocator)
    }
    append(&pm.goal_atoms, goal)
}

// Compute pragmatic value (negative distance from preferences)
compute_pragmatic_value :: proc(
    pred: model.PredictionVector,
    prefs: ^PreferenceModel,
) -> f64 {
    pred_features := model.prediction_to_features(&pred)
    
    // Weighted squared distance from preferences
    value: f64 = 0
    for i := 0; i < 16; i += 1 {
        diff := pred_features[i] - prefs.preferred_observations[i]
        value -= prefs.preference_weights[i] * diff * diff
    }
    
    return value
}

// Compute epistemic value (expected information gain)
compute_epistemic_value :: proc(
    gm: ^model.GenerativeModel,
    pred: model.PredictionVector,
) -> f64 {
    // Epistemic value is higher when prediction variance is high
    // (we expect to learn more from uncertain predictions)
    
    // But we also want to reduce uncertainty, so:
    // Expected info gain ≈ current_entropy - expected_posterior_entropy
    
    current_entropy := gm.beliefs.entropy
    
    // Expected posterior entropy (after observing prediction)
    // Approximation: entropy reduces proportionally to variance reduction
    expected_entropy := current_entropy * (1 - 0.1)  // 10% reduction per observation
    
    info_gain := current_entropy - expected_entropy
    
    // Negative because we want to minimize EFE (info gain is good)
    return -info_gain
}

// =============================================================================
// BELIEF UPDATING (PERCEPTUAL INFERENCE)
// =============================================================================

// Update beliefs to minimize free energy
minimize_free_energy_perception :: proc(
    gm: ^model.GenerativeModel,
    observations: ^sensors.ObservationVector,
    iterations: int = 10,
    learning_rate: f64 = 0.1,
) -> FreeEnergyComponents {
    final_fe := FreeEnergyComponents{}
    
    for iter := 0; iter < iterations; iter += 1 {
        // Generate predictions from current beliefs
        predictions := model.generative_model_predict(gm, nil)  // nil world state uses beliefs
        
        // Compute free energy
        fe := compute_free_energy(gm, observations, predictions)
        
        // Update beliefs based on prediction error
        update_beliefs_gradient(gm, observations, predictions, learning_rate)
        
        final_fe = fe
        
        // Early stopping if free energy is low enough
        if fe.total_free_energy < 0.01 {
            break
        }
    }
    
    return final_fe
}

// Gradient-based belief update
update_beliefs_gradient :: proc(
    gm: ^model.GenerativeModel,
    observations: ^sensors.ObservationVector,
    predictions: model.PredictionVector,
    lr: f64,
) {
    obs_features := sensors.observation_vector_to_features(observations)
    pred_features := model.prediction_to_features(&predictions)
    
    // Update attention beliefs based on observed values
    bs := gm.beliefs
    
    // Simple gradient: move beliefs toward observations
    obs_idx := 3  // avg_sti
    bs.attention_beliefs.expected_avg_sti += lr * (obs_features[obs_idx] - bs.attention_beliefs.expected_avg_sti)
    
    obs_idx = 4  // focus_size
    bs.attention_beliefs.expected_focus_size += lr * (obs_features[obs_idx] - bs.attention_beliefs.expected_focus_size)
    
    obs_idx = 5  // total_sti
    bs.attention_beliefs.expected_total_sti += lr * (obs_features[obs_idx] - bs.attention_beliefs.expected_total_sti)
    
    // Recompute entropy
    model.belief_state_entropy(bs)
}

// =============================================================================
// ACTION SELECTION (ACTIVE INFERENCE)
// =============================================================================

// Select action to minimize expected free energy
select_action_minimize_efe :: proc(
    gm: ^model.GenerativeModel,
    available_policies: []PolicyOption,
    preferences: ^PreferenceModel,
    horizon: int = 3,
) -> (PolicyOption, f64) {
    if len(available_policies) == 0 {
        return PolicyOption{}, math.INF_F64
    }
    
    best_policy := available_policies[0]
    best_efe := math.INF_F64
    
    for policy in available_policies {
        // Simulate policy over horizon
        predictions := simulate_policy(gm, policy, horizon)
        
        // Compute expected free energy
        efe := compute_expected_free_energy(gm, predictions, preferences)
        
        if efe.total < best_efe {
            best_efe = efe.total
            best_policy = policy
        }
    }
    
    return best_policy, best_efe
}

// PolicyOption represents a possible action/policy
PolicyOption :: struct {
    name:           string,
    rule_indices:   []int,      // Indices into rule base
    priority:       f64,
    estimated_cost: f64,
}

// Simulate a policy forward in time
simulate_policy :: proc(
    gm: ^model.GenerativeModel,
    policy: PolicyOption,
    horizon: int,
) -> []model.PredictionVector {
    predictions := make([]model.PredictionVector, horizon)
    
    // Simple forward simulation using generative model
    current_pred := model.generative_model_sample_transition(gm, nil)
    
    for t := 0; t < horizon; t += 1 {
        predictions[t] = current_pred
        
        // Apply policy effects (simplified)
        current_pred.expected_inference_count += f64(len(policy.rule_indices)) * 0.1
        current_pred.expected_atom_count += current_pred.expected_atoms_added - current_pred.expected_atoms_removed
        
        // Simulate next step
        current_pred.expected_atoms_added *= 0.9  // Decay
        current_pred.expected_atoms_removed *= 0.9
    }
    
    return predictions
}

// =============================================================================
// PRECISION OPTIMIZATION
// =============================================================================

// PrecisionState tracks precision parameters
PrecisionState :: struct {
    sensory_precision:      f64,
    prior_precision:        f64,
    policy_precision:       f64,
    
    // Adaptive precision
    sensory_precision_rate: f64,
    volatility_estimate:    f64,
}

// Update precision based on prediction error history
update_precision :: proc(
    ps: ^PrecisionState,
    prediction_error_history: []f64,
    learning_rate: f64 = 0.1,
) {
    if len(prediction_error_history) < 2 {
        return
    }
    
    // Compute variance of prediction errors
    mean: f64 = 0
    for pe in prediction_error_history {
        mean += pe
    }
    mean /= f64(len(prediction_error_history))
    
    variance: f64 = 0
    for pe in prediction_error_history {
        diff := pe - mean
        variance += diff * diff
    }
    variance /= f64(len(prediction_error_history))
    
    // Update volatility estimate
    ps.volatility_estimate = (1 - learning_rate) * ps.volatility_estimate + learning_rate * variance
    
    // Adjust precision inversely to volatility
    // Higher volatility -> lower precision (trust observations less)
    if ps.volatility_estimate > 0 {
        ps.sensory_precision = 1.0 / (1.0 + ps.volatility_estimate)
    }
}
