-- WhyNot V17: engineVersion 8 second-round cutoff tie policy
-- 1) Re-rank only the second-round boundary tie with first-round totals.
-- 2) Persist only the still-tied boundary as a host-started system roulette.
-- 3) Reuse score_boundary_runoffs; final-star-vote roulette policy is untouched.

BEGIN;

ALTER TABLE public.score_boundary_runoffs
  DROP CONSTRAINT IF EXISTS score_boundary_runoffs_source_reason_check;
ALTER TABLE public.score_boundary_runoffs
  ADD CONSTRAINT score_boundary_runoffs_source_reason_check
  CHECK (source_reason IN (
    'AI_INSUFFICIENT_EVIDENCE',
    'AI_UNAVAILABLE',
    'FIRST_SCORE_TIE_ROULETTE'
  ));

CREATE OR REPLACE FUNCTION public.prepare_second_round_tiebreak_v17(
  p_room_id TEXT,
  p_round_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_round public.evaluation_rounds%ROWTYPE;
  v_snapshot JSONB;
  v_boundary_ids TEXT[] := ARRAY[]::TEXT[];
  v_second_guaranteed_ids TEXT[] := ARRAY[]::TEXT[];
  v_first_guaranteed_ids TEXT[] := ARRAY[]::TEXT[];
  v_first_boundary_ids TEXT[] := ARRAY[]::TEXT[];
  v_combined_guaranteed_ids TEXT[] := ARRAY[]::TEXT[];
  v_server_selected_ids TEXT[] := ARRAY[]::TEXT[];
  v_engine_version INT;
  v_remaining_slots INT;
  v_roulette_slots INT;
  v_first_cutoff BIGINT;
  v_first_score_stats JSONB := '{}'::JSONB;
  v_next_status TEXT;
BEGIN
  SELECT * INTO v_round
  FROM public.evaluation_rounds
  WHERE id = p_round_id AND room_id = p_room_id
  FOR UPDATE;

  IF NOT FOUND
     OR v_round.evaluation_method <> 'SCORE_ONLY'
     OR v_round.stage <> 'EVALUATION'
     OR v_round.parent_round_id IS NULL THEN
    RAISE EXCEPTION '부모 1차 회차가 있는 2차 SCORE_ONLY 평가만 처리할 수 있습니다.';
  END IF;

  SELECT engine_version INTO STRICT v_engine_version
  FROM public.rooms WHERE id = p_room_id;
  IF v_engine_version < 8 THEN
    RAISE EXCEPTION 'engineVersion 8 이상 회의만 V17 동점 정책을 사용할 수 있습니다.';
  END IF;

  v_snapshot := COALESCE(v_round.result_snapshot, '{}'::JSONB);
  IF COALESCE(v_snapshot->>'aggregationStatus', '') IN ('READY_TO_FINALIZE', 'AWAITING_ROULETTE', 'COMPLETED') THEN
    RETURN v_snapshot;
  END IF;
  IF COALESCE(v_snapshot->>'aggregationStatus', '') <> 'AWAITING_AI' THEN
    RAISE EXCEPTION '2차 컷라인 동점 집계 상태가 아닙니다.';
  END IF;

  v_boundary_ids := ARRAY(
    SELECT JSONB_ARRAY_ELEMENTS_TEXT(COALESCE(v_snapshot->'boundaryTieIdeaIds', '[]'::JSONB))
  );
  v_second_guaranteed_ids := ARRAY(
    SELECT JSONB_ARRAY_ELEMENTS_TEXT(COALESCE(v_snapshot->'guaranteedSurvivorIdeaIds', '[]'::JSONB))
  );
  v_remaining_slots := COALESCE((v_snapshot->>'remainingSlots')::INT, 0);
  IF CARDINALITY(v_boundary_ids) <= v_remaining_slots OR v_remaining_slots < 1 THEN
    RAISE EXCEPTION '재비교가 필요한 2차 경계 동점 후보가 없습니다.';
  END IF;

  WITH first_scores AS (
    SELECT boundary.idea_id,
           COALESCE(SUM(evaluation.overall_score), 0)::BIGINT AS total_score
    FROM UNNEST(v_boundary_ids) boundary(idea_id)
    LEFT JOIN public.evaluations evaluation
      ON evaluation.room_id = p_room_id
     AND evaluation.round_id = v_round.parent_round_id
     AND evaluation.idea_id = boundary.idea_id
     AND evaluation.overall_score IS NOT NULL
    GROUP BY boundary.idea_id
  )
  SELECT JSONB_OBJECT_AGG(idea_id, jsonb_build_object('totalScore', total_score))
  INTO v_first_score_stats
  FROM first_scores;

  WITH first_scores AS (
    SELECT key AS idea_id, (value->>'totalScore')::BIGINT AS total_score
    FROM JSONB_EACH(v_first_score_stats)
  )
  SELECT total_score INTO v_first_cutoff
  FROM first_scores
  ORDER BY total_score DESC, idea_id
  OFFSET v_remaining_slots - 1 LIMIT 1;

  WITH first_scores AS (
    SELECT key AS idea_id, (value->>'totalScore')::BIGINT AS total_score
    FROM JSONB_EACH(v_first_score_stats)
  )
  SELECT
    COALESCE(ARRAY_AGG(idea_id ORDER BY total_score DESC, idea_id)
      FILTER (WHERE total_score > v_first_cutoff), ARRAY[]::TEXT[]),
    COALESCE(ARRAY_AGG(idea_id ORDER BY idea_id)
      FILTER (WHERE total_score = v_first_cutoff), ARRAY[]::TEXT[])
  INTO v_first_guaranteed_ids, v_first_boundary_ids
  FROM first_scores;

  v_combined_guaranteed_ids := v_second_guaranteed_ids || v_first_guaranteed_ids;
  v_roulette_slots := v_remaining_slots - CARDINALITY(v_first_guaranteed_ids);

  IF CARDINALITY(v_first_boundary_ids) > v_roulette_slots THEN
    v_next_status := 'AWAITING_ROULETTE';
    v_server_selected_ids := ARRAY[]::TEXT[];
  ELSE
    v_next_status := 'READY_TO_FINALIZE';
    v_server_selected_ids := v_combined_guaranteed_ids || v_first_boundary_ids;
  END IF;

  v_snapshot := v_snapshot || jsonb_build_object(
    'aggregationStatus', v_next_status,
    'originalSecondRoundBoundaryTieIdeaIds', v_boundary_ids,
    'firstRoundScoreStats', v_first_score_stats,
    'firstRoundBoundaryScore', v_first_cutoff,
    'guaranteedSurvivorIdeaIds', v_combined_guaranteed_ids,
    'boundaryTieIdeaIds', CASE
      WHEN v_next_status = 'AWAITING_ROULETTE' THEN to_jsonb(v_first_boundary_ids)
      ELSE '[]'::JSONB
    END,
    'remainingSlots', CASE WHEN v_next_status = 'AWAITING_ROULETTE' THEN v_roulette_slots ELSE 0 END,
    'serverSelectedIdeaIds', to_jsonb(v_server_selected_ids),
    'aiTiebreakRequired', FALSE,
    'tiebreakPolicy', 'SECOND_SCORE_THEN_FIRST_SCORE_THEN_ROULETTE'
  );

  UPDATE public.evaluation_rounds
  SET result_snapshot = v_snapshot,
      aggregation_status = 'PROCESSING'
  WHERE id = p_round_id AND room_id = p_room_id;

  RETURN v_snapshot;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_second_round_tiebreak_v17(TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_second_round_tiebreak_v17(TEXT, TEXT)
  TO service_role;

-- Reuse V16's strict candidate/count/application checks. The compatibility
-- state exists only inside this transaction and is cleaned before commit.
CREATE OR REPLACE FUNCTION public.apply_score_boundary_roulette_result_v17(
  p_room_id TEXT,
  p_round_id TEXT,
  p_runoff_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_round public.evaluation_rounds%ROWTYPE;
  v_runoff public.score_boundary_runoffs%ROWTYPE;
  v_snapshot JSONB;
  v_result JSONB;
BEGIN
  SELECT * INTO v_round
  FROM public.evaluation_rounds
  WHERE id = p_round_id AND room_id = p_room_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '2차 점수 평가 회차를 찾을 수 없습니다.'; END IF;
  IF v_round.status = 'COMPLETED' THEN RETURN v_round.result_snapshot; END IF;

  SELECT * INTO v_runoff
  FROM public.score_boundary_runoffs
  WHERE id = p_runoff_id AND room_id = p_room_id AND round_id = p_round_id
  FOR UPDATE;
  IF NOT FOUND
     OR v_runoff.source_reason <> 'FIRST_SCORE_TIE_ROULETTE'
     OR v_runoff.status <> 'COMPLETED'
     OR v_runoff.resolution_method <> 'AUTO_RANDOM' THEN
    RAISE EXCEPTION '완료된 V17 컷라인 룰렛만 적용할 수 있습니다.';
  END IF;

  v_snapshot := COALESCE(v_round.result_snapshot, '{}'::JSONB);
  IF COALESCE(v_snapshot->>'aggregationStatus', '') <> 'AWAITING_ROULETTE'
     OR COALESCE((v_snapshot->>'aiTiebreakRequired')::BOOLEAN, FALSE) THEN
    RAISE EXCEPTION '현재 회차가 V17 컷라인 룰렛 대기 상태가 아닙니다.';
  END IF;

  UPDATE public.evaluation_rounds
  SET result_snapshot = v_snapshot || jsonb_build_object(
        'aggregationStatus', 'AWAITING_AI',
        'aiTiebreakRequired', TRUE
      )
  WHERE id = p_round_id AND room_id = p_room_id;

  v_result := public.apply_score_boundary_runoff_result_v16(
    p_room_id,
    p_round_id,
    p_runoff_id
  );
  v_result := v_result || jsonb_build_object(
    'aiTiebreakRequired', FALSE,
    'aiTiebreak', jsonb_build_object('used', FALSE),
    'tiebreakPolicy', 'SECOND_SCORE_THEN_FIRST_SCORE_THEN_ROULETTE'
  );

  UPDATE public.evaluation_rounds
  SET result_snapshot = v_result
  WHERE id = p_round_id AND room_id = p_room_id;
  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_score_boundary_roulette_result_v17(TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_score_boundary_roulette_result_v17(TEXT, TEXT, TEXT)
  TO service_role;

COMMIT;
