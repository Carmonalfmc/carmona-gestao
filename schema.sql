-- CARMONA Gestão de Aulas: estrutura do banco no Supabase
-- Como usar: abra o projeto no Supabase, vá em SQL Editor, cole este arquivo inteiro e clique em Run.
-- Pode rodar mais de uma vez sem perder dados.
-- Todas as tabelas levam o prefixo gestao_ para conviver com outras tabelas no mesmo projeto.

create table if not exists public.gestao_locais (
  id            text primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome          text not null,
  bairro        text,
  contato       text,
  obs           text,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.gestao_alunos (
  id            text primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome          text not null,
  whatsapp      text,
  local_id      text,
  nivel         text,
  plano         text not null default 'mensal' check (plano in ('mensal', 'pacote', 'avulsa')),
  valor         numeric(10, 2) not null default 0,
  dia_venc      integer default 10,
  aulas_pacote  integer default 8,
  obs           text,
  ativo         boolean not null default true,
  desde         date,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.gestao_aulas (
  id            text primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  aluno_id      text not null references public.gestao_alunos (id) on delete cascade,
  local_id      text,
  data          date not null,
  hora          text not null,
  dur           integer not null default 60,
  status        text not null default 'agendada' check (status in ('agendada', 'dada', 'falta', 'cancelada')),
  obs           text,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.gestao_cobrancas (
  id            text primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  aluno_id      text not null references public.gestao_alunos (id) on delete cascade,
  tipo          text not null default 'mensalidade' check (tipo in ('mensalidade', 'pacote', 'avulsa', 'outro')),
  descricao     text,
  valor         numeric(10, 2) not null default 0,
  venc          date not null,
  pago_em       date,
  forma         text,
  ref           text,
  qtd           integer default 0,
  criado_em     date,
  aula_id       text,
  atualizado_em timestamptz not null default now()
);

create table if not exists public.gestao_config (
  user_id       uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  dados         jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

create index if not exists gestao_alunos_user_idx    on public.gestao_alunos (user_id);
create index if not exists gestao_locais_user_idx    on public.gestao_locais (user_id);
create index if not exists gestao_aulas_user_data    on public.gestao_aulas (user_id, data);
create index if not exists gestao_aulas_aluno_idx    on public.gestao_aulas (aluno_id);
create index if not exists gestao_cobrancas_user_ven on public.gestao_cobrancas (user_id, venc);
create index if not exists gestao_cobrancas_aluno    on public.gestao_cobrancas (aluno_id);

-- Marca a hora de cada alteração
create or replace function public.gestao_marcar_atualizacao() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.atualizado_em = now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['gestao_locais', 'gestao_alunos', 'gestao_aulas', 'gestao_cobrancas', 'gestao_config'] loop
    execute format('drop trigger if exists trg_gestao_atualizado on public.%I', t);
    execute format('create trigger trg_gestao_atualizado before update on public.%I for each row execute function public.gestao_marcar_atualizacao()', t);
  end loop;
end $$;

-- Segurança por linha: cada conta só enxerga e altera os próprios dados
do $$
declare t text;
begin
  foreach t in array array['gestao_locais', 'gestao_alunos', 'gestao_aulas', 'gestao_cobrancas', 'gestao_config'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists gestao_dono_total on public.%I', t);
    execute format('create policy gestao_dono_total on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
  end loop;
end $$;
