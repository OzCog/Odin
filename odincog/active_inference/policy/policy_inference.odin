// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Policy Inference
//
// This module implements policy selection as inference.
// Policies are sequences of rules that can be evaluated and selected
// based on expected free energy minimization.

package odincog_policy_inference

import "core:mem"
import "core:math"
import "core:time"
import "../model"
import "../inference"
import "../../reasoning/ure"

// =============================================================================
// POLICY TYPES
// =============================================================================

// Policy represents a complete action sequence
Policy :: struct {
    name:               string,
    
    // Sequence of rules to apply
    rules:              [dynamic]^ure.Rule,
    
    // Expected outcomes
    expected_outcomes:  [dynamic]model.PredictionVector,
    
    // Policy evaluation
    expected_fe:        f64,
    pragmatic_value:    f64,
    epistemic_value:    f64,
    
    // Prior probability (habit strength)
    prior:              f64,
    
    // Posterior probability after evaluation
    posterior:          f64,
    
    // Execution state
    current_step:       int,
    completed:          bool,
    
    // Statistics
    times_selected:     int,
    times_successful:   int,
    avg_outcome:        f64,
    
    allocator:          mem.Allocator,
}

// PolicyTree represents a branching policy structure
PolicyTree :: struct {
    root:               ^PolicyNode,
    depth:              int,
    total_nodes:        int,
    allocator:          mem.Allocator,
}

// PolicyNode is a node in the policy tree
PolicyNode :: struct {
    rule:               ^ure.Rule,
    children:           [dynamic]^PolicyNode,
    parent:             ^PolicyNode,
    
    // Node evaluation
    value:              f64,
    visits:             int,
    
    // UCB exploration term
    exploration_bonus:  f64,
    
    // Predicted state after this action
    predicted_state:    model.PredictionVector,
}

// =============================================================================
// POLICY LIFECYCLE
// =============================================================================

// Create a policy
policy_create :: proc(
    name: string,
    allocator := context.allocator,
) -> ^Policy {
    p := new(Policy, allocator)
    p.name = name
    p.rules = make([dynamic]^ure.Rule, allocator)
    p.expected_outcomes = make([dynamic]model.PredictionVector, allocator)
    p.prior = 1.0
    p.allocator = allocator
    return p
}

// Destroy a policy
policy_destroy :: proc(p: ^Policy) {
    if p == nil {
        return
    }
    delete(p.rules)
    delete(p.expected_outcomes)
    free(p, p.allocator)
}

// Add a rule to a policy
policy_add_rule :: proc(p: ^Policy, rule: ^ure.Rule) {
    append(&p.rules, rule)
}

// =============================================================================
// POLICY EVALUATION
// =============================================================================

// Evaluate a policy to compute expected free energy
policy_evaluate :: proc(
    p: ^Policy,
    gm: ^model.GenerativeModel,
    prefs: ^inference.PreferenceModel,
    horizon: int = 3,
) -> f64 {
    // Clear previous outcomes
    clear(&p.expected_outcomes)
    
    // Simulate policy forward
    current_pred := model.generative_model_predict(gm, nil)
    
    total_efe: f64 = 0
    discount: f64 = 1.0
    discount_factor: f64 = 0.95
    
    for t := 0; t < horizon; t += 1 {
        // Apply rule effects (simplified)
        if t < len(p.rules) {
            rule := p.rules[t]
            
            // Estimate rule effects on prediction
            current_pred.expected_inference_count += 1
            current_pred.expected_atom_count += rule.weight * 0.1
        }
        
        append(&p.expected_outcomes, current_pred)
        
        // Compute EFE for this timestep
        efe := compute_timestep_efe(current_pred, prefs, gm)
        total_efe += discount * efe
        
        discount *= discount_factor
        
        // Simulate transition
        current_pred.expected_atoms_added *= 0.9
        current_pred.expected_atoms_removed *= 0.9
    }
    
    p.expected_fe = total_efe
    
    // Decompose into pragmatic and epistemic components
    p.pragmatic_value = compute_pragmatic_component(p, prefs)
    p.epistemic_value = compute_epistemic_component(p, gm)
    
    return total_efe
}

// Compute EFE for a single timestep
compute_timestep_efe :: proc(
    pred: model.PredictionVector,
    prefs: ^inference.PreferenceModel,
    gm: ^model.GenerativeModel,
) -> f64 {
    // Pragmatic: distance from preferences
    pragmatic := inference.compute_pragmatic_value(pred, prefs)
    
    // Epistemic: expected uncertainty reduction
    epistemic := inference.compute_epistemic_value(gm, pred)
    
    // Risk: expected complexity
    risk := pred.prediction_variance
    
    return pragmatic + epistemic + risk
}

// Compute pragmatic component of policy value
compute_pragmatic_component :: proc(
    p: ^Policy,
    prefs: ^inference.PreferenceModel,
) -> f64 {
    total: f64 = 0
    
    for pred in p.expected_outcomes {
        total += inference.compute_pragmatic_value(pred, prefs)
    }
    
    if len(p.expected_outcomes) > 0 {
        return total / f64(len(p.expected_outcomes))
    }
    return 0
}

// Compute epistemic component of policy value
compute_epistemic_component :: proc(
    p: ^Policy,
    gm: ^model.GenerativeModel,
) -> f64 {
    total: f64 = 0
    
    for pred in p.expected_outcomes {
        total += inference.compute_epistemic_value(gm, pred)
    }
    
    if len(p.expected_outcomes) > 0 {
        return total / f64(len(p.expected_outcomes))
    }
    return 0
}

// =============================================================================
// POLICY SELECTION
// =============================================================================

// PolicySelector manages policy selection
PolicySelector :: struct {
    policies:           [dynamic]^Policy,
    
    // Selection parameters
    temperature:        f64,  // Softmax temperature
    prior_weight:       f64,  // Weight on prior probabilities
    
    // Last selection
    last_selected:      ^Policy,
    last_posterior:     [dynamic]f64,
    
    allocator:          mem.Allocator,
}

// Create policy selector
policy_selector_create :: proc(allocator := context.allocator) -> ^PolicySelector {
    ps := new(PolicySelector, allocator)
    ps.policies = make([dynamic]^Policy, allocator)
    ps.last_posterior = make([dynamic]f64, allocator)
    ps.temperature = 1.0
    ps.prior_weight = 0.5
    ps.allocator = allocator
    return ps
}

// Destroy policy selector
policy_selector_destroy :: proc(ps: ^PolicySelector) {
    if ps == nil {
        return
    }
    
    for p in ps.policies {
        policy_destroy(p)
    }
    delete(ps.policies)
    delete(ps.last_posterior)
    free(ps, ps.allocator)
}

// Add a policy to the selector
policy_selector_add :: proc(ps: ^PolicySelector, p: ^Policy) {
    append(&ps.policies, p)
}

// Select a policy using softmax over negative EFE
policy_selector_select :: proc(
    ps: ^PolicySelector,
    gm: ^model.GenerativeModel,
    prefs: ^inference.PreferenceModel,
) -> ^Policy {
    if len(ps.policies) == 0 {
        return nil
    }
    
    // Evaluate all policies
    efes := make([]f64, len(ps.policies), context.temp_allocator)
    for i, p in ps.policies {
        efes[i] = policy_evaluate(p, gm, prefs)
    }
    
    // Compute softmax probabilities
    clear(&ps.last_posterior)
    
    // Find max for numerical stability
    max_neg_efe: f64 = -math.INF_F64
    for efe in efes {
        neg_efe := -efe
        if neg_efe > max_neg_efe {
            max_neg_efe = neg_efe
        }
    }
    
    // Compute unnormalized probabilities
    sum: f64 = 0
    for i, p in ps.policies {
        // Combine prior with EFE
        neg_efe := -efes[i]
        log_prob := (neg_efe - max_neg_efe) / ps.temperature + ps.prior_weight * math.ln(p.prior)
        prob := math.exp(log_prob)
        append(&ps.last_posterior, prob)
        sum += prob
    }
    
    // Normalize
    for &prob in ps.last_posterior {
        prob /= sum
    }
    
    // Sample from distribution (or take argmax)
    best_idx := 0
    best_prob: f64 = 0
    for i, prob in ps.last_posterior {
        if prob > best_prob {
            best_prob = prob
            best_idx = i
        }
    }
    
    ps.last_selected = ps.policies[best_idx]
    return ps.last_selected
}

// =============================================================================
// POLICY TREE SEARCH
// =============================================================================

// Create policy tree
policy_tree_create :: proc(depth: int = 3, allocator := context.allocator) -> ^PolicyTree {
    pt := new(PolicyTree, allocator)
    pt.depth = depth
    pt.allocator = allocator
    return pt
}

// Destroy policy tree
policy_tree_destroy :: proc(pt: ^PolicyTree) {
    if pt == nil {
        return
    }
    
    if pt.root != nil {
        policy_node_destroy(pt.root, pt.allocator)
    }
    
    free(pt, pt.allocator)
}

// Destroy a policy node and its children
policy_node_destroy :: proc(node: ^PolicyNode, allocator: mem.Allocator) {
    for child in node.children {
        policy_node_destroy(child, allocator)
    }
    delete(node.children)
    free(node, allocator)
}

// Build policy tree from rule base
policy_tree_build :: proc(
    pt: ^PolicyTree,
    rb: ^ure.RuleBase,
    gm: ^model.GenerativeModel,
) {
    if pt.root != nil {
        policy_node_destroy(pt.root, pt.allocator)
    }
    
    // Create root node (no action)
    pt.root = new(PolicyNode, pt.allocator)
    pt.root.children = make([dynamic]^PolicyNode, pt.allocator)
    pt.total_nodes = 1
    
    // Expand tree
    policy_tree_expand(pt, pt.root, rb, gm, 0)
}

// Expand a node in the policy tree
policy_tree_expand :: proc(
    pt: ^PolicyTree,
    node: ^PolicyNode,
    rb: ^ure.RuleBase,
    gm: ^model.GenerativeModel,
    depth: int,
) {
    if depth >= pt.depth {
        return
    }
    
    rules := ure.rulebase_get_rules(rb)
    
    for rule in rules {
        // Create child node for each possible action
        child := new(PolicyNode, pt.allocator)
        child.rule = rule
        child.parent = node
        child.children = make([dynamic]^PolicyNode, pt.allocator)
        
        // Predict state after action
        child.predicted_state = model.generative_model_predict(gm, nil)
        child.predicted_state.expected_inference_count += 1
        
        append(&node.children, child)
        pt.total_nodes += 1
        
        // Recursively expand (with pruning)
        if rule.weight > 0.1 {  // Only expand promising branches
            policy_tree_expand(pt, child, rb, gm, depth + 1)
        }
    }
}

// Search policy tree using UCB1
policy_tree_search :: proc(
    pt: ^PolicyTree,
    prefs: ^inference.PreferenceModel,
    iterations: int = 100,
) -> ^Policy {
    if pt.root == nil || len(pt.root.children) == 0 {
        return nil
    }
    
    // UCB search
    for _ in 0..<iterations {
        // Select leaf
        leaf := policy_tree_select_leaf(pt.root)
        
        // Evaluate
        value := policy_tree_evaluate_leaf(leaf, prefs)
        
        // Backpropagate
        policy_tree_backpropagate(leaf, value)
    }
    
    // Return best child as policy
    best_child := policy_tree_best_child(pt.root)
    if best_child == nil {
        return nil
    }
    
    // Construct policy from path
    policy := policy_create("tree_search", pt.allocator)
    node := best_child
    for node != nil && node.rule != nil {
        append(&policy.rules, node.rule)
        
        // Continue to best child
        node = policy_tree_best_child(node)
    }
    
    return policy
}

// Select leaf node for expansion
policy_tree_select_leaf :: proc(node: ^PolicyNode) -> ^PolicyNode {
    if len(node.children) == 0 {
        return node
    }
    
    // UCB1 selection
    best_child: ^PolicyNode = nil
    best_ucb: f64 = -math.INF_F64
    
    parent_visits := f64(node.visits) + 1
    
    for child in node.children {
        // UCB1 = value + c * sqrt(ln(parent_visits) / child_visits)
        exploitation := child.value
        exploration := 2.0 * math.sqrt(math.ln(parent_visits) / f64(child.visits + 1))
        ucb := exploitation + exploration
        
        if ucb > best_ucb {
            best_ucb = ucb
            best_child = child
        }
    }
    
    if best_child != nil {
        return policy_tree_select_leaf(best_child)
    }
    return node
}

// Evaluate a leaf node
policy_tree_evaluate_leaf :: proc(
    node: ^PolicyNode,
    prefs: ^inference.PreferenceModel,
) -> f64 {
    // Simple evaluation based on predicted state
    pred := &node.predicted_state
    pred_features := model.prediction_to_features(pred)
    
    // Distance from preferences
    value: f64 = 0
    for i := 0; i < 16; i += 1 {
        diff := pred_features[i] - prefs.preferred_observations[i]
        value -= prefs.preference_weights[i] * diff * diff
    }
    
    // Normalize
    return value / 16
}

// Backpropagate value through tree
policy_tree_backpropagate :: proc(node: ^PolicyNode, value: f64) {
    current := node
    for current != nil {
        current.visits += 1
        current.value += (value - current.value) / f64(current.visits)
        current = current.parent
    }
}

// Get best child of a node
policy_tree_best_child :: proc(node: ^PolicyNode) -> ^PolicyNode {
    if len(node.children) == 0 {
        return nil
    }
    
    best: ^PolicyNode = nil
    best_value: f64 = -math.INF_F64
    
    for child in node.children {
        if child.value > best_value {
            best_value = child.value
            best = child
        }
    }
    
    return best
}

// =============================================================================
// HABIT FORMATION
// =============================================================================

// HabitMemory stores successful policy patterns
HabitMemory :: struct {
    patterns:           map[string]HabitPattern,
    max_patterns:       int,
    decay_rate:         f64,
    allocator:          mem.Allocator,
}

// HabitPattern represents a learned action pattern
HabitPattern :: struct {
    policy_name:        string,
    context_features:   [16]f64,  // Observations when successful
    strength:           f64,
    times_used:         int,
    last_used:          time.Time,
}

// Create habit memory
habit_memory_create :: proc(max_patterns: int = 100, allocator := context.allocator) -> ^HabitMemory {
    hm := new(HabitMemory, allocator)
    hm.patterns = make(map[string]HabitPattern, allocator)
    hm.max_patterns = max_patterns
    hm.decay_rate = 0.99
    hm.allocator = allocator
    return hm
}

// Destroy habit memory
habit_memory_destroy :: proc(hm: ^HabitMemory) {
    if hm == nil {
        return
    }
    delete(hm.patterns)
    free(hm, hm.allocator)
}

// Record a successful policy as habit
habit_memory_record :: proc(
    hm: ^HabitMemory,
    policy_name: string,
    context: [16]f64,
    success: bool,
) {
    if pattern, ok := hm.patterns[policy_name]; ok {
        // Update existing pattern
        pattern.times_used += 1
        pattern.last_used = time.now()
        
        if success {
            pattern.strength = min(pattern.strength + 0.1, 1.0)
        } else {
            pattern.strength = max(pattern.strength - 0.05, 0.0)
        }
        
        // Update context (running average)
        for i := 0; i < 16; i += 1 {
            pattern.context_features[i] = 0.9 * pattern.context_features[i] + 0.1 * context[i]
        }
        
        hm.patterns[policy_name] = pattern
    } else if success {
        // Create new pattern
        hm.patterns[policy_name] = HabitPattern{
            policy_name = policy_name,
            context_features = context,
            strength = 0.5,
            times_used = 1,
            last_used = time.now(),
        }
    }
    
    // Decay old patterns
    habit_memory_decay(hm)
    
    // Prune if needed
    if len(hm.patterns) > hm.max_patterns {
        habit_memory_prune(hm)
    }
}

// Decay habit strengths
habit_memory_decay :: proc(hm: ^HabitMemory) {
    for name, &pattern in hm.patterns {
        pattern.strength *= hm.decay_rate
    }
}

// Prune weakest habits
habit_memory_prune :: proc(hm: ^HabitMemory) {
    // Find weakest
    min_strength: f64 = 2.0
    weakest: string
    
    for name, pattern in hm.patterns {
        if pattern.strength < min_strength {
            min_strength = pattern.strength
            weakest = name
        }
    }
    
    delete_key(&hm.patterns, weakest)
}

// Get habit-based prior for policy
habit_memory_prior :: proc(
    hm: ^HabitMemory,
    policy_name: string,
    current_context: [16]f64,
) -> f64 {
    pattern, ok := hm.patterns[policy_name]
    if !ok {
        return 0.1  // Base prior for unknown policies
    }
    
    // Compute context similarity
    similarity: f64 = 0
    for i := 0; i < 16; i += 1 {
        diff := current_context[i] - pattern.context_features[i]
        similarity -= diff * diff
    }
    similarity = math.exp(similarity / 16)  // Normalize
    
    // Prior = habit strength * context similarity
    return pattern.strength * similarity
}
