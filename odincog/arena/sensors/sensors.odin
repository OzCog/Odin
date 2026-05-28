// OdinCog - AIGLA (Active Inference Game Loop Agent)
// Sensor System
//
// This module implements the observation system for the active inference agent.
// Sensors gather information from the AtomSpace and external sources to create
// unified observation vectors for the cognitive cycle.

package odincog_sensors

import "core:mem"
import "core:time"
import "core:math"
import "core:sync"
import "../../core/atom"
import "../../core/atomspace"
import "../../core/types"
import "../state"

// =============================================================================
// OBSERVATION TYPES
// =============================================================================

// ObservationType categorizes different sources of observation
ObservationType :: enum {
    // Internal AtomSpace observations
    ATOM_ADDED,
    ATOM_REMOVED,
    TV_CHANGED,
    AV_CHANGED,
    PATTERN_MATCHED,
    INFERENCE_COMPLETED,
    
    // Attention observations
    ENTERED_FOCUS,
    LEFT_FOCUS,
    STI_SPIKE,
    
    // External observations
    EXTERNAL_INPUT,
    FILE_CHANGED,
    NETWORK_EVENT,
    
    // Meta observations
    TICK_COMPLETED,
    ENERGY_CHANGED,
    GOAL_ACHIEVED,
}

// Observation represents a single sensory event
Observation :: struct {
    type:           ObservationType,
    timestamp:      time.Time,
    tick:           u64,
    
    // Source of observation
    source:         ObservationSource,
    
    // Numeric observation data
    value:          f64,
    confidence:     f64,
    
    // Associated atoms (if applicable)
    handles:        []atom.Handle,
    
    // Raw data (type-specific)
    data:           rawptr,
    data_size:      int,
}

// ObservationSource identifies where an observation came from
ObservationSource :: enum {
    ATOMSPACE,
    ECAN,
    URE,
    EXTERNAL,
    INTERNAL,
}

// =============================================================================
// OBSERVATION VECTOR
// =============================================================================

// ObservationVector is a dense representation of recent observations
ObservationVector :: struct {
    // Current tick observations
    observations:       [dynamic]Observation,
    
    // Aggregated statistics
    atom_count:         f64,
    link_count:         f64,
    node_count:         f64,
    avg_sti:            f64,
    focus_size:         f64,
    total_sti:          f64,
    inference_count:    f64,
    
    // Delta since last tick
    atoms_added:        int,
    atoms_removed:      int,
    tvs_changed:        int,
    avs_changed:        int,
    
    // Attention events
    focus_entries:      int,
    focus_exits:        int,
    
    // External events
    external_events:    int,
    
    // Energy metrics
    free_energy:        f64,
    prediction_error:   f64,
    surprisal:          f64,
    
    // Timestamp
    timestamp:          time.Time,
    tick:               u64,
    
    allocator:          mem.Allocator,
}

// Create observation vector
observation_vector_create :: proc(allocator := context.allocator) -> ^ObservationVector {
    ov := new(ObservationVector, allocator)
    ov.observations = make([dynamic]Observation, allocator)
    ov.allocator = allocator
    return ov
}

// Destroy observation vector
observation_vector_destroy :: proc(ov: ^ObservationVector) {
    if ov == nil {
        return
    }
    
    for &obs in ov.observations {
        if obs.handles != nil {
            delete(obs.handles, ov.allocator)
        }
    }
    delete(ov.observations)
    free(ov, ov.allocator)
}

// Reset observation vector for new tick
observation_vector_reset :: proc(ov: ^ObservationVector) {
    for &obs in ov.observations {
        if obs.handles != nil {
            delete(obs.handles, ov.allocator)
        }
    }
    clear(&ov.observations)
    
    ov.atoms_added = 0
    ov.atoms_removed = 0
    ov.tvs_changed = 0
    ov.avs_changed = 0
    ov.focus_entries = 0
    ov.focus_exits = 0
    ov.external_events = 0
    ov.prediction_error = 0
    ov.surprisal = 0
}

// Add an observation
observation_vector_add :: proc(ov: ^ObservationVector, obs: Observation) {
    append(&ov.observations, obs)
    
    // Update counters
    #partial switch obs.type {
        case .ATOM_ADDED:
            ov.atoms_added += 1
        case .ATOM_REMOVED:
            ov.atoms_removed += 1
        case .TV_CHANGED:
            ov.tvs_changed += 1
        case .AV_CHANGED:
            ov.avs_changed += 1
        case .ENTERED_FOCUS:
            ov.focus_entries += 1
        case .LEFT_FOCUS:
            ov.focus_exits += 1
        case .EXTERNAL_INPUT, .FILE_CHANGED, .NETWORK_EVENT:
            ov.external_events += 1
    }
}

// Convert to dense feature vector
observation_vector_to_features :: proc(ov: ^ObservationVector) -> [16]f64 {
    features: [16]f64
    
    features[0] = ov.atom_count
    features[1] = ov.link_count
    features[2] = ov.node_count
    features[3] = ov.avg_sti
    features[4] = ov.focus_size
    features[5] = ov.total_sti
    features[6] = ov.inference_count
    features[7] = f64(ov.atoms_added)
    features[8] = f64(ov.atoms_removed)
    features[9] = f64(ov.tvs_changed)
    features[10] = f64(ov.avs_changed)
    features[11] = f64(ov.focus_entries)
    features[12] = f64(ov.focus_exits)
    features[13] = ov.free_energy
    features[14] = ov.prediction_error
    features[15] = ov.surprisal
    
    return features
}

// =============================================================================
// SENSOR INTERFACE
// =============================================================================

// Sensor is the interface for all sensors
Sensor :: struct {
    name:           string,
    enabled:        bool,
    priority:       int,
    
    // Sensor function
    sense_fn:       proc(sensor: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector),
    
    // User data
    user_data:      rawptr,
    
    allocator:      mem.Allocator,
}

// Create a new sensor
sensor_create :: proc(
    name: string,
    sense_fn: proc(^Sensor, ^state.WorldState, ^ObservationVector),
    priority: int = 0,
    allocator := context.allocator,
) -> ^Sensor {
    s := new(Sensor, allocator)
    s.name = name
    s.enabled = true
    s.priority = priority
    s.sense_fn = sense_fn
    s.allocator = allocator
    return s
}

// Destroy a sensor
sensor_destroy :: proc(s: ^Sensor) {
    if s == nil {
        return
    }
    free(s, s.allocator)
}

// Run a sensor
sensor_sense :: proc(s: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector) {
    if s.enabled && s.sense_fn != nil {
        s.sense_fn(s, ws, ov)
    }
}

// =============================================================================
// SENSOR MANAGER
// =============================================================================

// SensorManager coordinates all sensors
SensorManager :: struct {
    sensors:        [dynamic]^Sensor,
    
    // Current observation vector
    current_obs:    ^ObservationVector,
    
    // Previous tick's observation (for delta computation)
    previous_obs:   ^ObservationVector,
    
    // Reference to world state
    world_state:    ^state.WorldState,
    
    // Synchronization
    lock:           sync.Mutex,
    
    allocator:      mem.Allocator,
}

// Create sensor manager
sensor_manager_create :: proc(
    ws: ^state.WorldState,
    allocator := context.allocator,
) -> ^SensorManager {
    sm := new(SensorManager, allocator)
    sm.sensors = make([dynamic]^Sensor, allocator)
    sm.current_obs = observation_vector_create(allocator)
    sm.previous_obs = observation_vector_create(allocator)
    sm.world_state = ws
    sm.allocator = allocator
    
    // Register default sensors
    sensor_manager_register_defaults(sm)
    
    return sm
}

// Destroy sensor manager
sensor_manager_destroy :: proc(sm: ^SensorManager) {
    if sm == nil {
        return
    }
    
    for s in sm.sensors {
        sensor_destroy(s)
    }
    delete(sm.sensors)
    
    observation_vector_destroy(sm.current_obs)
    observation_vector_destroy(sm.previous_obs)
    
    free(sm, sm.allocator)
}

// Register a sensor
sensor_manager_register :: proc(sm: ^SensorManager, s: ^Sensor) {
    sync.guard(&sm.lock)
    append(&sm.sensors, s)
    
    // Sort by priority (higher first)
    for i := len(sm.sensors) - 1; i > 0; i -= 1 {
        if sm.sensors[i].priority > sm.sensors[i-1].priority {
            sm.sensors[i], sm.sensors[i-1] = sm.sensors[i-1], sm.sensors[i]
        } else {
            break
        }
    }
}

// Unregister a sensor
sensor_manager_unregister :: proc(sm: ^SensorManager, name: string) {
    sync.guard(&sm.lock)
    
    for i := 0; i < len(sm.sensors); i += 1 {
        if sm.sensors[i].name == name {
            sensor_destroy(sm.sensors[i])
            ordered_remove(&sm.sensors, i)
            return
        }
    }
}

// Run all sensors and produce observation vector
sensor_manager_observe :: proc(sm: ^SensorManager) -> ^ObservationVector {
    sync.guard(&sm.lock)
    
    // Swap buffers
    sm.previous_obs, sm.current_obs = sm.current_obs, sm.previous_obs
    observation_vector_reset(sm.current_obs)
    
    // Set timestamp
    sm.current_obs.timestamp = time.now()
    sm.current_obs.tick = sm.world_state.tick
    
    // Run all sensors
    for s in sm.sensors {
        sensor_sense(s, sm.world_state, sm.current_obs)
    }
    
    return sm.current_obs
}

// Get current observations
sensor_manager_get_observations :: proc(sm: ^SensorManager) -> ^ObservationVector {
    return sm.current_obs
}

// Get previous observations
sensor_manager_get_previous :: proc(sm: ^SensorManager) -> ^ObservationVector {
    return sm.previous_obs
}

// =============================================================================
// DEFAULT SENSORS
// =============================================================================

// Register default sensors
sensor_manager_register_defaults :: proc(sm: ^SensorManager) {
    // AtomSpace stats sensor
    sensor_manager_register(sm, sensor_create(
        "atomspace_stats",
        proc(s: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector) {
            stats := atomspace.atomspace_stats(ws.atomspace)
            ov.atom_count = f64(stats.total_atoms)
            ov.node_count = f64(stats.total_nodes)
            ov.link_count = f64(stats.total_links)
        },
        100,  // High priority
        sm.allocator,
    ))
    
    // Attention stats sensor
    sensor_manager_register(sm, sensor_create(
        "attention_stats",
        proc(s: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector) {
            summary := ws.attention_summary
            ov.total_sti = f64(summary.total_sti)
            ov.focus_size = f64(summary.atoms_in_focus)
            
            // Calculate average STI
            if ov.atom_count > 0 {
                ov.avg_sti = ov.total_sti / ov.atom_count
            }
        },
        90,
        sm.allocator,
    ))
    
    // Transaction sensor (detects changes)
    sensor_manager_register(sm, sensor_create(
        "transaction_sensor",
        proc(s: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector) {
            for &t in ws.transactions {
                obs := Observation{
                    timestamp = t.timestamp,
                    tick = t.tick,
                    source = .ATOMSPACE,
                }
                
                #partial switch t.type {
                    case .ADD_NODE, .ADD_LINK:
                        obs.type = .ATOM_ADDED
                    case .REMOVE_ATOM:
                        obs.type = .ATOM_REMOVED
                    case .UPDATE_TV:
                        obs.type = .TV_CHANGED
                    case .UPDATE_AV:
                        obs.type = .AV_CHANGED
                }
                
                observation_vector_add(ov, obs)
            }
        },
        80,
        sm.allocator,
    ))
    
    // Inference state sensor
    sensor_manager_register(sm, sensor_create(
        "inference_sensor",
        proc(s: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector) {
            inf_state := ws.inference_state
            ov.inference_count = f64(inf_state.pending_inferences)
            ov.free_energy = inf_state.free_energy
        },
        70,
        sm.allocator,
    ))
}

// =============================================================================
// SPECIALIZED SENSORS
// =============================================================================

// AtomDeltaSensor tracks changes to specific atom types
AtomDeltaSensorData :: struct {
    tracked_types:      []types.AtomType,
    previous_counts:    map[types.AtomType]int,
}

create_atom_delta_sensor :: proc(
    tracked_types: []types.AtomType,
    allocator := context.allocator,
) -> ^Sensor {
    data := new(AtomDeltaSensorData, allocator)
    data.tracked_types = tracked_types
    data.previous_counts = make(map[types.AtomType]int, allocator)
    
    s := sensor_create(
        "atom_delta",
        proc(sensor: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector) {
            data := cast(^AtomDeltaSensorData)sensor.user_data
            
            for t in data.tracked_types {
                handles := atomspace.get_atoms_by_type(ws.atomspace, t, false)
                current_count := len(handles)
                
                if prev, ok := data.previous_counts[t]; ok {
                    delta := current_count - prev
                    if delta != 0 {
                        obs := Observation{
                            type = delta > 0 ? .ATOM_ADDED : .ATOM_REMOVED,
                            timestamp = time.now(),
                            tick = ws.tick,
                            source = .ATOMSPACE,
                            value = f64(abs(delta)),
                        }
                        observation_vector_add(ov, obs)
                    }
                }
                
                data.previous_counts[t] = current_count
            }
        },
        60,
        allocator,
    )
    
    s.user_data = data
    return s
}

// FocusSensor tracks atoms entering/leaving attentional focus
FocusSensorData :: struct {
    previous_focus:     map[atom.Handle]bool,
}

create_focus_sensor :: proc(allocator := context.allocator) -> ^Sensor {
    data := new(FocusSensorData, allocator)
    data.previous_focus = make(map[atom.Handle]bool, allocator)
    
    s := sensor_create(
        "focus",
        proc(sensor: ^Sensor, ws: ^state.WorldState, ov: ^ObservationVector) {
            data := cast(^FocusSensorData)sensor.user_data
            
            // Get current focus set
            current_focus := make(map[atom.Handle]bool, context.temp_allocator)
            
            it := atomspace.atomspace_iterator(ws.atomspace)
            for {
                a, h, ok := atomspace.atomspace_iterate(&it)
                if !ok { break }
                
                if a.attention_value.sti >= atom.ATTENTIONAL_FOCUS_BOUNDARY {
                    current_focus[h] = true
                    
                    // Check if newly entered
                    if !(h in data.previous_focus) {
                        obs := Observation{
                            type = .ENTERED_FOCUS,
                            timestamp = time.now(),
                            tick = ws.tick,
                            source = .ECAN,
                            value = f64(a.attention_value.sti),
                        }
                        observation_vector_add(ov, obs)
                    }
                }
            }
            
            // Check for exits
            for h in data.previous_focus {
                if !(h in current_focus) {
                    obs := Observation{
                        type = .LEFT_FOCUS,
                        timestamp = time.now(),
                        tick = ws.tick,
                        source = .ECAN,
                    }
                    observation_vector_add(ov, obs)
                }
            }
            
            // Update previous focus
            clear(&data.previous_focus)
            for h in current_focus {
                data.previous_focus[h] = true
            }
        },
        50,
        allocator,
    )
    
    s.user_data = data
    return s
}

// =============================================================================
// SENSOR FUSION
// =============================================================================

// Compute prediction error between expected and actual observations
compute_prediction_error :: proc(predicted: ^ObservationVector, actual: ^ObservationVector) -> f64 {
    pred_features := observation_vector_to_features(predicted)
    actual_features := observation_vector_to_features(actual)
    
    // Mean squared error
    mse: f64 = 0
    for i := 0; i < len(pred_features); i += 1 {
        diff := pred_features[i] - actual_features[i]
        mse += diff * diff
    }
    
    return mse / f64(len(pred_features))
}

// Compute surprisal (negative log likelihood)
compute_surprisal :: proc(ov: ^ObservationVector) -> f64 {
    // Simple heuristic based on change magnitude
    changes := f64(ov.atoms_added + ov.atoms_removed + ov.tvs_changed + ov.avs_changed)
    
    if changes == 0 {
        return 0
    }
    
    // Normalize by atom count
    if ov.atom_count > 0 {
        changes /= ov.atom_count
    }
    
    // Negative log (more changes = higher surprisal)
    if changes > 0 && changes < 1 {
        return -math.ln(1.0 - changes)
    }
    
    return changes * 10  // Scale for large changes
}
