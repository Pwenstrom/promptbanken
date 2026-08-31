-- Självförsörjande, rollback-wrappad verifiering av privata original
-- och immutable Open-revisioner. Säker att köra mot staging/produktion.
begin;

create temp table open_submission_results(test text primary key, ok boolean not null, detail text not null);
grant select,insert,update,delete on open_submission_results to authenticated;
create temp table open_submission_ids(submission_id uuid primary key);
grant select,insert,update,delete on open_submission_ids to authenticated;

insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('71000000-0000-0000-0000-000000000001','authenticated','authenticated','open.owner@example.test',now(),'{}','{}',now(),now()),
 ('71000000-0000-0000-0000-000000000002','authenticated','authenticated','open.other@example.test',now(),'{}','{}',now(),now());
insert into public.workspaces(id,name,slug,type,plan,owner_user_id,max_prompts,mcp_enabled)
values
 ('72000000-0000-0000-0000-000000000001','Open owner','open-owner-fixture','personal','free','71000000-0000-0000-0000-000000000001',3,true),
 ('72000000-0000-0000-0000-000000000002','Open other','open-other-fixture','personal','free','71000000-0000-0000-0000-000000000002',3,true);
insert into public.profiles(user_id,workspace_id,role) values
 ('71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','editor'),
 ('71000000-0000-0000-0000-000000000002','72000000-0000-0000-0000-000000000002','editor');
insert into public.creator_profiles(id,user_id,slug,display_name,status) values
 ('73000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','open-owner-fixture','Open Owner','draft'),
 ('73000000-0000-0000-0000-000000000002','71000000-0000-0000-0000-000000000002','open-other-fixture','Open Other','draft');

set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000001',true);
insert into public.content_items(id,workspace_id,owner_user_id,created_by,type,module,title,slug,content,status,visibility)
values('74000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001',
 '71000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001',
 'prompt','kommun','Privat prompt','privat-prompt-fixture','Första privata versionen','draft','private');

do $$ declare v_result jsonb; begin
 v_result:=public.submit_creator_prompt('74000000-0000-0000-0000-000000000001',true,true,true,true);
 insert into open_submission_ids values((v_result->>'submission_id')::uuid);
 update public.content_items set content='Ny privat version' where id='74000000-0000-0000-0000-000000000001';
end $$;
reset role;

do $$ declare v_snapshot uuid; v_text text; v_status text; begin
 select submission_id into v_snapshot from open_submission_ids;
 select payload->>'prompt_text',submission_state into v_text,v_status from public.content_snapshots where id=v_snapshot;
 insert into open_submission_results values('original editable, snapshot frozen',
   v_text='Första privata versionen' and v_status='review',
   'snapshot='||coalesce(v_text,'<null>')||', state='||coalesce(v_status,'<null>'));
end $$;

do $$ declare v_row record; begin
 select * into v_row from public.list_my_library_items()
  where kind='prompt' and subject_id='74000000-0000-0000-0000-000000000001';
 insert into open_submission_results values('library separates access and Open state',
   v_row.access_label='private' and v_row.open_submission_state='review',
   'access='||coalesce(v_row.access_label,'<null>')||', open='||coalesce(v_row.open_submission_state,'<null>'));
end $$;

do $$ declare v_rejected boolean:=false; begin
 begin
  update public.content_snapshots set payload=jsonb_build_object('tampered',true)
   where purpose='open_submission' and subject_id='74000000-0000-0000-0000-000000000001';
 exception when others then v_rejected:=true; end;
 insert into open_submission_results values('snapshot payload is immutable',v_rejected,
   case when v_rejected then 'rejected as expected' else 'NOT rejected' end);
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-0000-0000-000000000002',true);
do $$ declare v_snapshot uuid; v_rejected boolean:=false; begin
 select submission_id into v_snapshot from open_submission_ids;
 begin perform public.withdraw_creator_open_submission(v_snapshot);
 exception when others then v_rejected:=true; end;
 insert into open_submission_results values('other user cannot withdraw submission',v_rejected,
   case when v_rejected then 'rejected as expected' else 'NOT rejected' end);
end $$;
reset role;

do $$ begin
 if exists(select 1 from open_submission_results where not ok) then
   raise exception 'Open submission verification failed: %',
     (select string_agg(test||' ('||detail||')','; ') from open_submission_results where not ok);
 end if;
end $$;
select * from open_submission_results order by test;
rollback;
