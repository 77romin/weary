grant delete on table public.content_reports to authenticated;

create policy "users can remove their own reports"
on public.content_reports for delete
to authenticated
using (reporter_id = (select auth.uid()));
