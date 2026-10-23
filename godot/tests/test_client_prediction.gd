extends "res://tests/test_base.gd"

const ClientPrediction = preload("res://net/client_prediction.gd")

func test_client_prediction_generates_immediate_local_movement() -> void:
	var predictor := ClientPrediction.new()
	var start_pos := Vector2.ZERO
	predictor.reset(start_pos)
	
	var move_input := {"move": Vector2(1.0, 0.0), "speed": 6.0}
	var predicted: Vector2 = predictor.predict_input(move_input, 0.1) # 100ms
	
	gt(predicted.x, 0.5, "local predicted position immediately moves forward")
	eq(predicted.y, 0.0, "lateral position unchanged")
	eq(predictor.get_pending_count(), 1, "pending buffer stores 1 unacknowledged input")

func test_reconciliation_acknowledges_clean_server_state() -> void:
	var predictor := ClientPrediction.new()
	predictor.reset(Vector2.ZERO)
	
	var input1 := {"move": Vector2(1.0, 0.0), "speed": 5.0}
	var input2 := {"move": Vector2(1.0, 0.0), "speed": 5.0}
	predictor.predict_input(input1, 0.1) # seq 1, pos (0.5, 0)
	predictor.predict_input(input2, 0.1) # seq 2, pos (1.0, 0)
	eq(predictor.get_pending_count(), 2, "2 inputs recorded")
	
	# Server processed seq 1, reports pos (0.5, 0)
	predictor.reconcile(1, Vector2(0.5, 0.0))
	eq(predictor.get_pending_count(), 1, "acknowledged input seq 1 evicted")
	near(predictor.get_render_pos().x, 1.0, 0.001, "render pos reflects current latest predicted state")

func test_reconciliation_applies_smooth_correction_for_minor_drift() -> void:
	var predictor := ClientPrediction.new()
	predictor.reset(Vector2.ZERO)
	
	predictor.predict_input({"move": Vector2(1.0, 0.0), "speed": 6.0}, 0.1) # predicted (0.6, 0)
	# Server reports obstacle or slow, actual pos was (0.45, 0)
	predictor.reconcile(1, Vector2(0.45, 0.0))
	
	# Smooth offset should be generated to avoid visual popping
	var offset: Vector2 = predictor.get_smooth_offset()
	gt(offset.x, 0.0, "smooth correction offset keeps render position smooth")
	
	# Decay over frames
	predictor.update_decay(0.05)
	lt(predictor.get_smooth_offset().x, offset.x, "smooth offset decays toward zero over time")

func test_large_divergence_snaps_instantly() -> void:
	var predictor := ClientPrediction.new()
	predictor.reset(Vector2.ZERO)
	
	predictor.predict_input({"move": Vector2(1.0, 0.0), "speed": 6.0}, 0.1)
	# Server knocked hero back 10 meters (e.g. displacement skill)
	predictor.reconcile(1, Vector2(-10.0, 0.0))
	
	near(predictor.get_render_pos().x, -10.0, 0.01, "large divergence snaps instantly to server authority")
	near(predictor.get_smooth_offset().length(), 0.0, 0.001, "no smooth sliding across screen on hard snap")

func test_predict_at_merges_frames_under_one_network_sequence() -> void:
	var predictor := ClientPrediction.new()
	predictor.reset(Vector2.ZERO)

	predictor.predict_at(Vector2(1.0, 0.0), 6.0, 0.02, 5)
	predictor.predict_at(Vector2(1.0, 0.0), 6.0, 0.03, 5)
	eq(predictor.get_pending_count(), 1, "frames sharing a sequence merge into one pending record")
	near(predictor.get_render_pos().x, 0.3, 0.001, "merged prediction accumulates both frames")

	predictor.reconcile(5, Vector2(0.3, 0.0))
	eq(predictor.get_pending_count(), 0, "server ack clears the matching network sequence")
	near(predictor.get_render_pos().x, 0.3, 0.001, "clean ack keeps predicted position")

func test_unknown_ack_rebases_and_replays_without_visual_jump() -> void:
	var predictor := ClientPrediction.new()
	predictor.reset(Vector2.ZERO)

	predictor.predict_at(Vector2(1.0, 0.0), 5.0, 0.1, 7)
	var before := predictor.get_render_pos()
	# 服务端还没处理 seq 7（可能刚重置过预测历史），只确认到 6。
	predictor.reconcile(6, Vector2.ZERO)
	eq(predictor.get_pending_count(), 1, "unacked sequence is replayed")
	near(predictor.get_render_pos().x, before.x, 0.001, "render position stays continuous across unknown ack")
	near(predictor.get_smooth_offset().length(), 0.0, 0.001, "rebase does not double-count the pending input")
