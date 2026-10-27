-- Profiles that still store the old letter forms have not chosen
-- among image, music, city, building, film, and book. Give them all six,
-- which is what the letters were already rotating through.
update public.profiles
set letter_forms = array['keyword', 'quote', 'image', 'music', 'city', 'building', 'film', 'book']
where (
  select coalesce(array_agg(item order by item), array[]::text[])
  from unnest(letter_forms) as item
) in (
  array['keyword', 'quote']::text[],
  array['image', 'keyword', 'music', 'quote']::text[]
);
