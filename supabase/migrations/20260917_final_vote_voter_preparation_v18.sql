-- WhyNot V18: external voters are configured only after final candidates exist.
-- Existing room settings, invitations, and registrations are preserved. These
-- guards apply only when voter-related state is created or changed.

BEGIN;

CREATE OR REPLACE FUNCTION public.assert_final_voter_preparation_v18(
  p_room_id TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_room public.rooms%ROWTYPE;
BEGIN
  SELECT * INTO v_room
  FROM public.rooms
  WHERE id = p_room_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '방을 찾을 수 없습니다.' USING ERRCODE = 'P0001';
  END IF;
  IF v_room.status <> 'ELIMINATION'
     OR COALESCE(v_room.final_vote_status, 'NOT_STARTED') <> 'NOT_STARTED'
     OR v_room.final_vote_roster_locked_at IS NOT NULL
     OR v_room.current_final_vote_cycle_id IS NOT NULL THEN
    RAISE EXCEPTION '외부 투표자는 최종 후보가 확정된 최종 별 투표 준비 단계에서만 변경할 수 있습니다.'
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_room_final_voter_settings_v18()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.external_voters_enabled IS DISTINCT FROM OLD.external_voters_enabled
     OR NEW.required_voter_count IS DISTINCT FROM OLD.required_voter_count THEN
    PERFORM public.assert_final_voter_preparation_v18(OLD.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS rooms_guard_final_voter_settings_v18 ON public.rooms;
CREATE TRIGGER rooms_guard_final_voter_settings_v18
BEFORE UPDATE OF external_voters_enabled, required_voter_count ON public.rooms
FOR EACH ROW EXECUTE FUNCTION public.guard_room_final_voter_settings_v18();

CREATE OR REPLACE FUNCTION public.guard_voter_invite_mutation_v18()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF COALESCE(NEW.invite_type, OLD.invite_type) = 'VOTER' THEN
    PERFORM public.assert_final_voter_preparation_v18(COALESCE(NEW.room_id, OLD.room_id));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS room_invites_guard_voter_mutation_v18 ON public.room_invites;
CREATE TRIGGER room_invites_guard_voter_mutation_v18
BEFORE INSERT OR UPDATE ON public.room_invites
FOR EACH ROW EXECUTE FUNCTION public.guard_voter_invite_mutation_v18();

CREATE OR REPLACE FUNCTION public.guard_voter_account_invite_mutation_v18()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF COALESCE(NEW.invite_role, OLD.invite_role) = 'VOTER' THEN
    PERFORM public.assert_final_voter_preparation_v18(COALESCE(NEW.room_id, OLD.room_id));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS room_account_invites_guard_voter_mutation_v18 ON public.room_account_invites;
CREATE TRIGGER room_account_invites_guard_voter_mutation_v18
BEFORE INSERT OR UPDATE ON public.room_account_invites
FOR EACH ROW EXECUTE FUNCTION public.guard_voter_account_invite_mutation_v18();

CREATE OR REPLACE FUNCTION public.guard_voter_registration_mutation_v18()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Canceling an incomplete final ballot intentionally reopens the same
  -- electorate before the room lock is cleared by the surrounding transaction.
  IF TG_OP = 'UPDATE' AND OLD.status = 'ACTIVE' AND NEW.status = 'WAITING' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT'
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.source IS DISTINCT FROM OLD.source THEN
    PERFORM public.assert_final_voter_preparation_v18(COALESCE(NEW.room_id, OLD.room_id));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS room_voter_registrations_guard_mutation_v18 ON public.room_voter_registrations;
CREATE TRIGGER room_voter_registrations_guard_mutation_v18
BEFORE INSERT OR UPDATE ON public.room_voter_registrations
FOR EACH ROW EXECUTE FUNCTION public.guard_voter_registration_mutation_v18();

REVOKE ALL ON FUNCTION public.assert_final_voter_preparation_v18(TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_room_final_voter_settings_v18()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_voter_invite_mutation_v18()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_voter_account_invite_mutation_v18()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_voter_registration_mutation_v18()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.assert_final_voter_preparation_v18(TEXT) TO service_role;

COMMIT;
