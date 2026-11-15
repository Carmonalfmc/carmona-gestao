-- CARMONA Scout: tabelas para o app do aluno
-- Cole no SQL Editor do Supabase e clique em Run.
-- Pode rodar mais de uma vez sem perder dados.

-- Perfil do aluno (email do aluno → id do aluno na gestão)
create table if not exists public.scout_perfis (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  aluno_id      text,              -- id na gestao_alunos (preenchido pelo Carmona)
  nome          text,
  atualizado_em timestamptz not null default now(),
  unique (user_id)
);

-- Partidas (criadas pelo Carmona, vistas pelo aluno)
create table if not exists public.scout_partidas (
  id            text primary key,
  coach_id      uuid not null references auth.users (id) on delete cascade,
  aluno_id      text not null,     -- id na gestao_alunos
  oponente      text not null default '',
  data          date not null,
  formato       text not null default '1 set, sem vantagem',
  placar        text not null default '',
  obs           text,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- Pontos da partida (preenchidos pelo Carmona via Scout ao vivo)
create table if not exists public.scout_pontos (
  id            text primary key,
  partida_id    text not null references public.scout_partidas (id) on delete cascade,
  coach_id      uuid not null references auth.users (id) on delete cascade,
  set_num       integer not null default 1,
  game_num      integer not null default 1,
  ponto_num     integer not null default 1,
  sacador       text not null check (sacador in ('aluno','oponente')),
  -- saque
  saque1        text check (saque1 in ('dentro','fora','rede','ace','dupla_falta')),
  saque2        text check (saque2 in ('dentro','fora','rede','ace','dupla_falta')),
  saque_forçou  boolean default false,
  -- resultado
  vencedor      text not null check (vencedor in ('aluno','oponente')),
  tipo_fim      text check (tipo_fim in ('winner','erro_nf','erro_f','ace','dupla_falta')),
  golpe_fim     text check (golpe_fim in ('forehand','backhand','volei_d','volei_e','smash','saque','sem_lado')),
  destino_fim   text check (destino_fim in ('rede','fundo','lateral')),
  zona_fim      text check (zona_fim in ('verde','amarela','vermelha','roxa')),
  -- rally
  num_bolas     integer default 1,
  criado_em     timestamptz not null default now()
);

-- Avaliações do professor para o aluno
create table if not exists public.scout_avaliacoes (
  id            text primary key,
  coach_id      uuid not null references auth.users (id) on delete cascade,
  aluno_id      text not null,
  data          date not null,
  texto         text not null,
  criado_em     timestamptz not null default now()
);

-- Temas que o aluno quer evoluir
create table if not exists public.scout_evolucao (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  temas         jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now(),
  unique (user_id)
);

-- Índices
create index if not exists scout_partidas_coach_idx on public.scout_partidas (coach_id);
create index if not exists scout_partidas_aluno_idx on public.scout_partidas (aluno_id);
create index if not exists scout_pontos_partida_idx on public.scout_pontos (partida_id);
create index if not exists scout_avaliacoes_aluno   on public.scout_avaliacoes (aluno_id);

-- Trigger de atualização
create or replace function public.scout_marcar_atualizacao() returns trigger
language plpgsql set search_path = '' as $$
begin new.atualizado_em = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['scout_perfis','scout_partidas','scout_evolucao'] loop
    execute format('drop trigger if exists trg_scout_atualizado on public.%I', t);
    execute format('create trigger trg_scout_atualizado before update on public.%I for each row execute function public.scout_marcar_atualizacao()', t);
  end loop;
end $$;

-- RLS: o coach lê e escreve tudo; o aluno lê as próprias partidas/pontos
do $$
declare t text;
begin
  foreach t in array array['scout_partidas','scout_pontos','scout_avaliacoes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists scout_coach_total on public.%I', t);
    execute format('drop policy if exists scout_aluno_leitura on public.%I', t);
    -- coach escreve tudo
    execute format('create policy scout_coach_total on public.%I for all to authenticated using (coach_id = (select auth.uid())) with check (coach_id = (select auth.uid()))', t);
  end loop;
end $$;

-- scout_perfis: cada aluno só vê e edita o próprio perfil
alter table public.scout_perfis enable row level security;
drop policy if exists scout_perfil_dono on public.scout_perfis;
create policy scout_perfil_dono on public.scout_perfis for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- scout_evolucao: cada aluno só vê e edita os próprios temas
alter table public.scout_evolucao enable row level security;
drop policy if exists scout_evolucao_dono on public.scout_evolucao;
create policy scout_evolucao_dono on public.scout_evolucao for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Partidas: o aluno lê as partidas onde aparece como aluno_id via perfil
-- (o coach vincula o aluno_id ao user_id do aluno no scout_perfis)
drop policy if exists scout_partida_aluno_leitura on public.scout_partidas;
create policy scout_partida_aluno_leitura on public.scout_partidas for select to authenticated
  using (
    aluno_id in (
      select aluno_id from public.scout_perfis
      where user_id = (select auth.uid()) and aluno_id is not null
    )
  );

drop policy if exists scout_ponto_aluno_leitura on public.scout_pontos;
create policy scout_ponto_aluno_leitura on public.scout_pontos for select to authenticated
  using (
    partida_id in (
      select p.id from public.scout_partidas p
      join public.scout_perfis sp on sp.aluno_id = p.aluno_id
      where sp.user_id = (select auth.uid())
    )
  );

drop policy if exists scout_avaliacao_aluno_leitura on public.scout_avaliacoes;
create policy scout_avaliacao_aluno_leitura on public.scout_avaliacoes for select to authenticated
  using (
    aluno_id in (
      select aluno_id from public.scout_perfis
      where user_id = (select auth.uid()) and aluno_id is not null
    )
  );
