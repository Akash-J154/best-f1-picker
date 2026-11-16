-- Paste into Supabase: SQL Editor -> New query -> Run
create table if not exists participants (
  id bigint generated always as identity primary key,
  token uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now()
);
create table if not exists votes (
  participant_id bigint not null references participants(id) on delete cascade,
  item text not null,
  chosen_method text not null check (chosen_method in ('ours','interactvlm','milo')),
  display_order jsonb not null,
  created_at timestamptz not null default now(),
  primary key (participant_id, item)
);
alter table participants enable row level security;
alter table votes enable row level security;
revoke all on participants, votes from anon, authenticated;

create or replace function new_participant() returns table(pid bigint, tok uuid)
language sql security definer set search_path = public as $$
  insert into participants default values returning id, token;
$$;
create or replace function submit_vote(p_id bigint, p_tok uuid, p_item text, p_method text, p_order jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from participants where id = p_id and token = p_tok) then raise exception 'invalid participant'; end if;
  insert into votes(participant_id,item,chosen_method,display_order) values (p_id,p_item,p_method,p_order)
  on conflict (participant_id,item) do update set chosen_method=excluded.chosen_method, display_order=excluded.display_order, created_at=now();
end $$;
create or replace function withdraw_participant(p_id bigint, p_tok uuid) returns void
language sql security definer set search_path = public as $$
  delete from participants where id = p_id and token = p_tok;
$$;
create or replace function results() returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object(
    'participants', (select count(*) from participants),
    'votes', (select count(*) from votes),
    'points', coalesce((select jsonb_object_agg(chosen_method, n) from (select chosen_method, count(*) n from votes group by 1) t), '{}'::jsonb));
$$;
revoke all on function new_participant(), submit_vote(bigint,uuid,text,text,jsonb), withdraw_participant(bigint,uuid), results() from public;
grant execute on function new_participant(), submit_vote(bigint,uuid,text,text,jsonb), withdraw_participant(bigint,uuid), results() to anon;

-- Export all votes as JSON (run in the SQL editor any time):
-- select jsonb_agg(v) from (select participant_id, item, chosen_method, display_order, created_at from votes order by 1,2) v;
