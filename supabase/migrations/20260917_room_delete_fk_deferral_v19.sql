-- WhyNot V19: allow a room's existing CASCADE graph to finish before checking
-- cross-references between room-owned rows. Individual parent deletion remains
-- protected because the NO ACTION constraints are still checked at commit.

BEGIN;

ALTER TABLE public.evaluation_rounds
  DROP CONSTRAINT evaluation_rounds_parent_room_fk,
  ADD CONSTRAINT evaluation_rounds_parent_room_fk
    FOREIGN KEY (parent_round_id, room_id)
    REFERENCES public.evaluation_rounds(id, room_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.idea_versions
  DROP CONSTRAINT idea_versions_round_room_fk,
  ADD CONSTRAINT idea_versions_round_room_fk
    FOREIGN KEY (round_id, room_id)
    REFERENCES public.evaluation_rounds(id, room_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.evaluation_round_participants
  DROP CONSTRAINT evaluation_round_participants_member_fk,
  ADD CONSTRAINT evaluation_round_participants_member_fk
    FOREIGN KEY (room_id, user_id)
    REFERENCES public.participants(room_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.candidate_feedback
  DROP CONSTRAINT candidate_feedback_evaluator_snapshot_fk,
  ADD CONSTRAINT candidate_feedback_evaluator_snapshot_fk
    FOREIGN KEY (round_id, evaluator_id)
    REFERENCES public.evaluation_round_participants(round_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.refinement_cycles
  DROP CONSTRAINT refinement_cycles_source_round_fk,
  DROP CONSTRAINT refinement_cycles_refinement_round_fk,
  DROP CONSTRAINT refinement_cycles_creator_fk,
  ADD CONSTRAINT refinement_cycles_source_round_fk
    FOREIGN KEY (source_round_id, room_id)
    REFERENCES public.evaluation_rounds(id, room_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT refinement_cycles_refinement_round_fk
    FOREIGN KEY (refinement_round_id, room_id)
    REFERENCES public.evaluation_rounds(id, room_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT refinement_cycles_creator_fk
    FOREIGN KEY (room_id, created_by)
    REFERENCES public.participants(room_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.refinement_cycle_votes
  DROP CONSTRAINT refinement_cycle_votes_snapshot_member_fk,
  ADD CONSTRAINT refinement_cycle_votes_snapshot_member_fk
    FOREIGN KEY (source_round_id, user_id)
    REFERENCES public.evaluation_round_participants(round_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.round_deadline_audit
  DROP CONSTRAINT round_deadline_audit_member_fk,
  ADD CONSTRAINT round_deadline_audit_member_fk
    FOREIGN KEY (room_id, changed_by)
    REFERENCES public.participants(room_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.final_vote_ballots
  DROP CONSTRAINT final_vote_ballots_member_fk,
  ADD CONSTRAINT final_vote_ballots_member_fk
    FOREIGN KEY (room_id, user_id)
    REFERENCES public.participants(room_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.final_roulette_consents
  DROP CONSTRAINT final_roulette_consents_member_fk,
  ADD CONSTRAINT final_roulette_consents_member_fk
    FOREIGN KEY (room_id, user_id)
    REFERENCES public.participants(room_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.final_roulette_draws
  DROP CONSTRAINT final_roulette_draws_selected_idea_id_fkey,
  DROP CONSTRAINT final_roulette_draws_host_fk,
  ADD CONSTRAINT final_roulette_draws_selected_idea_id_fkey
    FOREIGN KEY (selected_idea_id)
    REFERENCES public.ideas(id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT final_roulette_draws_host_fk
    FOREIGN KEY (room_id, drawn_by)
    REFERENCES public.participants(room_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.score_boundary_runoff_ballots
  DROP CONSTRAINT score_boundary_runoff_ballots_member_fk,
  ADD CONSTRAINT score_boundary_runoff_ballots_member_fk
    FOREIGN KEY (room_id, user_id)
    REFERENCES public.participants(room_id, user_id)
    ON DELETE NO ACTION
    DEFERRABLE INITIALLY DEFERRED;

COMMIT;
