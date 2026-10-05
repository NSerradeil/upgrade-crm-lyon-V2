-- 55_cerveau_chunks.sql : index semantique du second cerveau (strates par RLS)
create extension if not exists vector;

create table if not exists public.cerveau_chunks (
  id         bigserial primary key,
  note_path  text not null,
  chunk_idx  int  not null,
  contenu    text not null,
  niveau     int2 not null check (niveau between 0 and 3),
  entite     text,
  crm_ref    text,
  embedding  vector(768) not null,
  maj_le     timestamptz not null default now(),
  unique (note_path, chunk_idx)
);

drop index if exists public.cerveau_chunks_embedding_idx;
create index if not exists cerveau_chunks_embedding_hnsw
  on public.cerveau_chunks using hnsw (embedding vector_cosine_ops);
create index if not exists cerveau_chunks_entite_idx on public.cerveau_chunks (entite);

alter table public.cerveau_chunks enable row level security;
alter table public.cerveau_chunks force row level security;
revoke all on public.cerveau_chunks from anon, authenticated;
revoke all on sequence public.cerveau_chunks_id_seq from anon, authenticated;

-- Pre-filtre strate : une session ne voit ni n'ecrit que les chunks <= son niveau_max.
-- niveau_max est pose par l'app a chaque transaction via set_config('cerveau.niveau_max', ...).
drop policy if exists cerveau_chunks_strate on public.cerveau_chunks;
create policy cerveau_chunks_strate on public.cerveau_chunks
  for all
  using (niveau <= coalesce(nullif(current_setting('cerveau.niveau_max', true), '')::int, 0))
  with check (niveau <= coalesce(nullif(current_setting('cerveau.niveau_max', true), '')::int, 0));

-- Role applicatif : ne peut jamais contourner le RLS.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'cerveau_app') then
    create role cerveau_app login nosuperuser nobypassrls;
  end if;
end $$;
alter role cerveau_app nosuperuser nobypassrls;
grant usage on schema public to cerveau_app;
grant select, insert, update, delete on public.cerveau_chunks to cerveau_app;
grant usage, select on sequence public.cerveau_chunks_id_seq to cerveau_app;
-- L'ecriture (ingestion) tourne avec niveau_max = 3 ; la lecture pose le niveau du demandeur.
