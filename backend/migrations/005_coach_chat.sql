-- Conversation history with the AI coach.
create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'coach')),
  content text not null,
  -- Things the coach did or offered in this reply (saved notes, suggested plan changes).
  actions jsonb not null default '[]',
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_user_created
  on chat_messages (user_id, created_at);

alter table chat_messages enable row level security;
create policy "own chat_messages" on chat_messages for all using (auth.uid() = user_id);
