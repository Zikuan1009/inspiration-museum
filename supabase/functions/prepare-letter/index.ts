// 为某一个本地日期提前写一封个性化来信。信封打开时不调用这里。
// 资料来自年龄、性别、地区、学校、简介、爱好、性格、职业。
// 收藏、点赞和写下的感悟另记在 interest_signals，不改写填写的爱好。
// Nano 按这些行为更新一句观察，观察不展示给用户。关键词和名言每天都写。
// 图片、音乐、城市、建筑、电影、书由用户在幕后勾选。一天只给一件，按 COMPANIONS 的顺序在已选种类里轮换。
// Ultra 只补一句「为什么是今天」，有行为时必须点名依据。
// 同一天的信只有在行为没有变化时才直接返回。

import { createClient } from "npm:@supabase/supabase-js@2";

const NANO = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B";
const ULTRA = "nvidia/Nemotron-3-Ultra-550b-a55b";
const FAL_SCHNELL = "https://fal.run/fal-ai/flux/schnell";
const STORED_FORMS = ["keyword", "quote", "image", "music", "city", "building", "film", "book", "none"] as const;
// 每天轮换的一件。以后加入新种类时，加在这个名单末尾，并在起草和信件卡片里接上它。
const COMPANIONS = ["image", "music", "city", "building", "film", "book"] as const;
type Companion = (typeof COMPANIONS)[number];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") return json({ error: "只接受 POST。" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ error: "请先登录。" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const nebiusKey = Deno.env.get("NEBIUS_API_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey || !nebiusKey) {
    return json({ error: "来信还没有准备好。" }, 500);
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "请先登录。" }, 401);
  const userId = userData.user.id;

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch {
    payload = {};
  }
  const letterDate = typeof payload.letter_date === "string"
    ? payload.letter_date.trim()
    : "";
  if (!allowedDate(letterDate)) {
    return json({ error: "这一天不能准备来信。" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const stamp = await signalStamp(admin, userId);
  const { data: existing } = await admin
    .from("daily_letters")
    .select("keyword, quote, music_title, image_url, signals_stamp")
    .eq("user_id", userId)
    .eq("letter_date", letterDate)
    .maybeSingle();

  const profile = await readProfile(supabase, userId);
  let signals = await readSignals(admin, userId);
  let liveStamp = stamp;
  let note = profile.observedNote;
  if (!sameStamp(profile.interestStamp, stamp)) {
    try {
      note = await refreshObservation(admin, nebiusKey, userId, stamp, signals);
    } catch (error) {
      console.log("observe failed", error instanceof Error ? error.name : "error");
    }
  }

  if (useBreakout(userId, letterDate, profile.breakoutRatio)) {
    if (hasLetter(existing)) return json({ ready: true, cached: true, source: "breakout" });
    const written = await writeBreakoutLetter(supabase, admin, userId, letterDate, liveStamp);
    if (written) return json({ ready: true, cached: false, source: "breakout" });
  }

  if (hasLetter(existing) && sameStamp(textOf(existing?.signals_stamp), liveStamp)) {
    return json({ ready: true, cached: true });
  }

  const moved = await signalStamp(admin, userId);
  if (moved !== liveStamp) {
    liveStamp = moved;
    signals = await readSignals(admin, userId);
    try {
      note = await refreshObservation(admin, nebiusKey, userId, liveStamp, signals);
    } catch (error) {
      console.log("observe failed", error instanceof Error ? error.name : "error");
    }
  }

  const posts = await recentPosts(supabase, userId);
  const allowed = chosenCompanions(profile.forms);
  const companion = nextCompanion(
    await previousCompanion(admin, userId, letterDate),
    allowed,
  );
  const forms = companion ? ["keyword", "quote", companion] : ["keyword", "quote"];
  const explore = useExplore(userId, letterDate, signals.length > 0);
  const avoidKeyword = cleanSentence(payload.avoid_keyword, 40);
  const avoidQuote = cleanSentence(payload.avoid_quote, 180);
  const previous = await previousLetters(
    admin,
    userId,
    profile.letterMemory,
    avoidKeyword || avoidQuote ? [{ keyword: avoidKeyword, quote: avoidQuote }] : [],
  );

  let draft: Draft;
  try {
    draft = await draftWithNano(
      nebiusKey,
      profile,
      posts,
      signals,
      note,
      explore,
      forms,
      previous,
      false,
    );
    if (repeatsLetter(draft, previous)) {
      draft = await draftWithNano(
        nebiusKey,
        profile,
        posts,
        signals,
        note,
        explore,
        forms,
        previous,
        true,
      );
    }
  } catch (error) {
    console.log("nano letter failed", error instanceof Error ? error.name : "error");
    return json({ error: "来信还没有准备好。" }, 502);
  }

  let whyToday = "";
  try {
    whyToday = await whyWithUltra(nebiusKey, draft, profile, signals, note, explore, forms);
  } catch (error) {
    console.log("ultra letter failed", error instanceof Error ? error.name : "error");
  }

  const beforeImage = await signalStamp(admin, userId);
  if (beforeImage !== liveStamp) return json({ ready: false, stale: true });

  let imageUrl = "";
  if (forms.includes("image") && draft.imageBrief) {
    imageUrl = await paintLetter(admin, Deno.env.get("FAL_KEY") ?? "", userId, letterDate, draft.imageBrief);
  }

  const beforeWrite = await signalStamp(admin, userId);
  if (beforeWrite !== liveStamp) return json({ ready: false, stale: true });

  const row = {
    user_id: userId,
    letter_date: letterDate,
    theme_name: "",
    sub_theme_name: "",
    keyword: draft.keyword,
    quote: draft.quote,
    quote_author: draft.quoteAuthor,
    music_title: companion === "music" ? draft.musicTitle : "",
    music_artist: companion === "music" ? draft.musicArtist : "",
    image_url: imageUrl,
    city_name: companion === "city" ? draft.cityName : "",
    city_country: companion === "city" ? draft.cityCountry : "",
    building_name: companion === "building" ? draft.buildingName : "",
    building_city: companion === "building" ? draft.buildingCity : "",
    film_title: companion === "film" ? draft.filmTitle : "",
    film_director: companion === "film" ? draft.filmDirector : "",
    book_title: companion === "book" ? draft.bookTitle : "",
    book_author: companion === "book" ? draft.bookAuthor : "",
    why_today: whyToday,
    forms,
    signals_stamp: liveStamp,
  };
  if (!hasLetter(row)) return json({ error: "来信还没有准备好。" }, 502);

  const { error: writeError } = await admin.from("daily_letters").upsert(row, {
    onConflict: "user_id,letter_date",
  });
  if (writeError) return json({ error: "来信还没有准备好。" }, 500);
  try {
    await rememberLetter(admin, userId, profile.letterMemory, row.keyword, row.quote);
  } catch (error) {
    console.log("memory failed", error instanceof Error ? error.name : "error");
  }
  return json({ ready: true, cached: false });
});

type Draft = {
  keyword: string;
  quote: string;
  quoteAuthor: string;
  musicTitle: string;
  musicArtist: string;
  imageBrief: string;
  cityName: string;
  cityCountry: string;
  buildingName: string;
  buildingCity: string;
  filmTitle: string;
  filmDirector: string;
  bookTitle: string;
  bookAuthor: string;
};

type Profile = {
  username: string;
  age: string;
  gender: string;
  location: string;
  school: string;
  bio: string;
  hobbies: string;
  personality: string;
  occupation: string;
  forms: string[];
  breakoutRatio: number;
  observedNote: string;
  interestStamp: string;
  letterMemory: string;
};

function hasLetter(row: Record<string, unknown> | null | undefined): boolean {
  if (!row) return false;
  const keyword = typeof row.keyword === "string" ? row.keyword.trim() : "";
  const quote = typeof row.quote === "string" ? row.quote.trim() : "";
  const music = typeof row.music_title === "string" ? row.music_title.trim() : "";
  const image = typeof row.image_url === "string" ? row.image_url.trim() : "";
  const city = typeof row.city_name === "string" ? row.city_name.trim() : "";
  const building = typeof row.building_name === "string" ? row.building_name.trim() : "";
  const film = typeof row.film_title === "string" ? row.film_title.trim() : "";
  const book = typeof row.book_title === "string" ? row.book_title.trim() : "";
  return Boolean(keyword || quote || music || image.startsWith("http") || city || building || film || book);
}

function allowedDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const target = Date.parse(`${value}T00:00:00Z`);
  if (Number.isNaN(target)) return false;
  const now = new Date();
  const utc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const delta = Math.round((target - utc) / 86_400_000);
  return delta >= -1 && delta <= 2;
}

async function readProfile(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<Profile> {
  const { data } = await supabase
    .from("profiles")
    .select("username, age, gender, location, school, bio, hobbies, personality, occupation, letter_forms, breakout_ratio, observed_note, interest_stamp, letter_memory")
    .eq("id", userId)
    .maybeSingle();
  const row = data ?? {};
  const picked = Array.isArray(row.letter_forms)
    ? row.letter_forms.map((item: unknown) => String(item))
    : [];
  const forms = STORED_FORMS.filter((form) => picked.includes(form));
  return {
    username: cleanSentence(row.username, 32),
    age: cleanSentence(row.age == null ? "" : String(row.age), 8),
    gender: cleanSentence(row.gender, 16),
    location: cleanSentence(row.location, 24),
    school: cleanSentence(row.school, 40),
    bio: cleanSentence(row.bio, 80),
    hobbies: cleanSentence(row.hobbies, 80),
    personality: cleanSentence(row.personality, 40),
    occupation: cleanSentence(row.occupation, 40),
    forms: forms.length > 0 ? [...forms] : ["keyword", "quote"],
    breakoutRatio: clampRatio(row.breakout_ratio),
    observedNote: cleanSentence(row.observed_note, 80),
    interestStamp: typeof row.interest_stamp === "string" ? row.interest_stamp.trim() : "",
    letterMemory: typeof row.letter_memory === "string" ? row.letter_memory : "",
  };
}

function personOf(profile: Profile): Record<string, string> {
  const fields: Record<string, string> = {
    name: profile.username,
    bio: profile.bio,
    age: profile.age,
    gender: profile.gender,
    location: profile.location,
    school: profile.school,
    hobbies: profile.hobbies,
    personality: profile.personality,
    occupation: profile.occupation,
  };
  return Object.fromEntries(
    Object.entries(fields).filter((entry) => entry[1].trim().length > 0),
  );
}

function clampRatio(value: unknown): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) return 30;
  return Math.max(0, Math.min(100, Math.round(parsed)));
}

function useBreakout(userId: string, letterDate: string, ratio: number): boolean {
  if (ratio <= 0) return false;
  if (ratio >= 100) return true;
  let hash = 0;
  const text = `${userId}:${letterDate}`;
  for (let i = 0; i < text.length; i++) {
    hash = (Math.imul(hash, 33) + text.charCodeAt(i)) >>> 0;
  }
  return (hash % 100) < ratio;
}

async function writeBreakoutLetter(
  supabase: ReturnType<typeof createClient>,
  admin: ReturnType<typeof createClient>,
  userId: string,
  letterDate: string,
  stamp: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("get_random_daily_letter", {
    target_user_id: userId,
  });
  if (error) return false;
  const row = asRow(data);
  if (!row) return false;
  const keyword = cleanSentence(row.keyword, 24);
  const quote = cleanSentence(row.quote, 160);
  if (!keyword && !quote) return false;
  const { error: writeError } = await admin.from("daily_letters").upsert({
    user_id: userId,
    letter_date: letterDate,
    theme_name: cleanSentence(row.theme_name, 24),
    sub_theme_name: cleanSentence(row.sub_theme_name, 24),
    keyword,
    quote,
    quote_author: "",
    music_title: "",
    music_artist: "",
    image_url: "",
    city_name: "",
    city_country: "",
    building_name: "",
    building_city: "",
    film_title: "",
    film_director: "",
    book_title: "",
    book_author: "",
    why_today: "",
    forms: ["breakout"],
    signals_stamp: stamp,
  }, { onConflict: "user_id,letter_date" });
  return !writeError;
}

function asRow(data: unknown): Record<string, unknown> | null {
  if (Array.isArray(data)) return asRow(data[0]);
  if (data && typeof data === "object") return data as Record<string, unknown>;
  return null;
}

type Signal = { kind: string; excerpt: string };

function sameStamp(stored: string, stamp: string): boolean {
  const left = stored.trim() || "none";
  const right = stamp.trim() || "none";
  return left === right;
}

function useExplore(userId: string, letterDate: string, hasSignals: boolean): boolean {
  if (!hasSignals) return false;
  let hash = 0;
  const text = `${userId}:${letterDate}:explore`;
  for (let i = 0; i < text.length; i++) {
    hash = (Math.imul(hash, 33) + text.charCodeAt(i)) >>> 0;
  }
  return (hash % 5) === 0;
}

async function signalStamp(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<string> {
  const { data } = await admin
    .from("interest_signals")
    .select("id")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(8);
  const ids = (data ?? [])
    .map((row) => (typeof row.id === "string" ? row.id : ""))
    .filter((id) => id.length > 0);
  return ids.length > 0 ? ids.join(",") : "none";
}

async function readSignals(
  admin: ReturnType<typeof createClient>,
  userId: string,
): Promise<Signal[]> {
  const { data } = await admin
    .from("interest_signals")
    .select("kind, excerpt")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(8);
  const signals: Signal[] = [];
  for (const row of data ?? []) {
    const kind = row.kind === "reflection" || row.kind === "save" || row.kind === "like"
      ? row.kind
      : "";
    const excerpt = cleanSentence(row.excerpt, 80);
    if (!kind || !excerpt) continue;
    signals.push({ kind, excerpt });
  }
  return signals;
}

async function refreshObservation(
  admin: ReturnType<typeof createClient>,
  apiKey: string,
  userId: string,
  stamp: string,
  signals: Signal[],
): Promise<string> {
  let note = "";
  if (signals.length > 0) {
    try {
      const raw = await complete(apiKey, NANO, [
        {
          role: "system",
          content:
            "Return JSON only: {\"observed_note\":\"one English sentence\"}. " +
            "From recent_signals, say which direction this person is moving toward. " +
            "Do not rewrite their declared hobbies, and do not claim an interest that is not in the signals. " +
            "Name one concrete piece of evidence. No quotation marks.",
        },
        {
          role: "user",
          content: JSON.stringify({ recent_signals: signals }),
        },
      ], 180, true);
      note = cleanSentence(readObject(raw).observed_note, 160);
    } catch (error) {
      console.log("observe nano failed", error instanceof Error ? error.name : "error");
    }
      if (!note) note = cleanSentence(`Recent evidence: ${signals[0].excerpt}`, 160);
  }
  const { error } = await admin
    .from("profiles")
    .update({ observed_note: note, interest_stamp: stamp })
    .eq("id", userId);
  if (error) throw new Error("observe write");
  return note;
}

async function recentPosts(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<string[]> {
  const { data } = await supabase
    .from("inspirations")
    .select("user_text, quote")
    .eq("author_id", userId)
    .order("created_at", { ascending: false })
    .limit(6);
  const lines: string[] = [];
  for (const row of data ?? []) {
    const raw = typeof row.user_text === "string" ? row.user_text : "";
    const hasSplit = raw.includes("\u001e");
    const parts = raw.split("\u001e");
    const title = hasSplit ? cleanSentence(parts[0] ?? "", 40) : "";
    const body = cleanSentence(hasSplit ? parts.slice(1).join("") : raw, 80);
    const quote = cleanSentence(row.quote, 60);
    const line = [title, body, quote].filter((part) => part.length > 0).join(" / ");
    if (line) lines.push(line);
  }
  return lines;
}

type PreviousLetter = {
  keyword: string;
  quote: string;
  musicTitle?: string;
  musicArtist?: string;
  pieceTitle?: string;
};

function parseMemory(raw: string): PreviousLetter[] {
  const items: PreviousLetter[] = [];
  for (const line of raw.split("\n")) {
    const parts = line.split("\u001e");
    const keyword = cleanSentence(parts[0], 40);
    const quote = cleanSentence(parts.slice(1).join(""), 80);
    if (!keyword && !quote) continue;
    items.push({ keyword, quote });
  }
  return items.slice(0, 8);
}

async function previousLetters(
  admin: ReturnType<typeof createClient>,
  userId: string,
  memory: string,
  extra: PreviousLetter[],
): Promise<PreviousLetter[]> {
  const { data } = await admin
    .from("daily_letters")
    .select("keyword, quote, music_title, music_artist, city_name, building_name, film_title, book_title")
    .eq("user_id", userId)
    .order("letter_date", { ascending: false })
    .limit(8);
  const merged: PreviousLetter[] = [];
  const seen = new Set<string>();
  const push = (item: PreviousLetter) => {
    const keyword = item.keyword.trim();
    const quote = item.quote.trim();
    const musicTitle = (item.musicTitle ?? "").trim();
    const musicArtist = (item.musicArtist ?? "").trim();
    const pieceTitle = (item.pieceTitle ?? "").trim();
    if (!keyword && !quote && !musicTitle && !pieceTitle) return;
    const mark = `${keyword}|${quote}|${musicTitle}|${pieceTitle}`;
    if (seen.has(mark)) return;
    seen.add(mark);
    merged.push({ keyword, quote, musicTitle, musicArtist, pieceTitle });
  };
  for (const item of extra) push(item);
  for (const item of parseMemory(memory)) push(item);
  for (const row of data ?? []) {
    push({
      keyword: cleanSentence(row.keyword, 40),
      quote: cleanSentence(row.quote, 80),
      musicTitle: cleanSentence(row.music_title, 80),
      musicArtist: cleanSentence(row.music_artist, 60),
      pieceTitle: [
        cleanSentence(row.city_name, 80),
        cleanSentence(row.building_name, 80),
        cleanSentence(row.film_title, 80),
        cleanSentence(row.book_title, 80),
      ].find((item) => item.length > 0) ?? "",
    });
  }
  return merged.slice(0, 8);
}

function repeatsLetter(draft: Draft, previous: PreviousLetter[]): boolean {
  const keyword = draft.keyword.trim();
  const quote = draft.quote.trim();
  const pieces = [
    draft.musicTitle,
    draft.cityName,
    draft.buildingName,
    draft.filmTitle,
    draft.bookTitle,
  ].map((item) => item.trim().toLowerCase()).filter((item) => item.length > 0);
  return previous.some((item) => {
    if (keyword && item.keyword && keyword === item.keyword) return true;
    if (quote && item.quote && quote === item.quote) return true;
    const prior = [
      item.musicTitle ?? "",
      item.pieceTitle ?? "",
    ].map((value) => value.trim().toLowerCase());
    return pieces.some((piece) => prior.includes(piece));
  });
}

async function rememberLetter(
  admin: ReturnType<typeof createClient>,
  userId: string,
  memory: string,
  keyword: string,
  quote: string,
): Promise<void> {
  const next = [{ keyword: keyword.trim(), quote: quote.trim() }, ...parseMemory(memory)]
    .filter((item) => item.keyword || item.quote)
    .slice(0, 8);
  const text = next.map((item) => `${item.keyword}\u001e${item.quote}`).join("\n");
  const { error } = await admin.from("profiles").update({ letter_memory: text }).eq("id", userId);
  if (error) throw new Error("memory write");
}

function chosenCompanions(forms: string[]): Companion[] {
  const picked = COMPANIONS.filter((item) => forms.includes(item));
  if (picked.length > 0) return [...picked];
  if (forms.includes("none")) return [];
  return [...COMPANIONS];
}

function companionOf(forms: string[]): Companion | "" {
  for (const item of COMPANIONS) {
    if (forms.includes(item)) return item;
  }
  return "";
}

function companionBrief(forms: string[]): string {
  const piece = companionOf(forms);
  if (!piece) {
    return "There is no rotating piece today. Leave music_title, music_artist, image_brief, and every city, building, film, and book field empty.";
  }
  const shared = "Choose it because this person might be interested, using hobbies, personality, occupation, location, recent_signals, and observed_note. When behavior and declared hobbies disagree, follow the behavior. Do not invent a name, a place, or a work. Do not repeat a title already present in avoid. Leave every other rotating field empty. ";
  switch (piece) {
    case "music":
      return "Today's rotating piece is music. Fill music_title and music_artist. music_title is one real released song, track, or classical work. music_artist is the performer or composer who actually recorded or wrote it. " + shared;
    case "city":
      return "Today's rotating piece is a city. Fill city_name and city_country. city_name is one real city. city_country is the country it is actually in. Do not choose the person's own location. " + shared;
    case "building":
      return "Today's rotating piece is a building. Fill building_name and building_city. building_name is one real building. building_city is the city where that building actually stands. " + shared;
    case "film":
      return "Today's rotating piece is a film. Fill film_title and film_director. film_title is one real released film. film_director is the person who actually directed it. " + shared;
    case "book":
      return "Today's rotating piece is a book. Fill book_title and book_author. book_title is one real published book. book_author is the person who actually wrote it. " + shared;
    default:
      return "Today's rotating piece is an image. Fill image_brief in English so it depicts this new keyword. The scene must be concrete and different from the letters in avoid. Do not draw blank paper, an empty room, or a white square. No text, watermark, or logo. Leave music_title, music_artist, and every place, building, film, and book field empty.";
  }
}

function nextCompanion(
  previous: Companion | "",
  allowed: readonly Companion[],
): Companion | "" {
  if (allowed.length === 0) return "";
  if (!previous) return allowed[0];
  const start = COMPANIONS.indexOf(previous);
  if (start < 0) return allowed[0];
  for (let step = 1; step <= COMPANIONS.length; step += 1) {
    const candidate = COMPANIONS[(start + step) % COMPANIONS.length];
    if (allowed.includes(candidate)) return candidate;
  }
  return allowed[0];
}

function columnText(row: Record<string, unknown>, key: string): string {
  const value = row[key];
  return typeof value === "string" ? value.trim() : "";
}

function readCompanion(row: Record<string, unknown> | null): Companion | "" {
  if (!row) return "";
  const forms = Array.isArray(row.forms) ? row.forms.map((item) => String(item)) : [];
  const listed = [...forms].reverse().find((item) =>
    (COMPANIONS as readonly string[]).includes(item)
  );
  const present = COMPANIONS.filter((item) => {
    if (item === "image") return columnText(row, "image_url").startsWith("http");
    if (item === "music") return columnText(row, "music_title").length > 0;
    if (item === "city") return columnText(row, "city_name").length > 0;
    if (item === "building") return columnText(row, "building_name").length > 0;
    if (item === "film") return columnText(row, "film_title").length > 0;
    return columnText(row, "book_title").length > 0;
  });
  if (present.length === 1) return present[0];
  if (listed && present.includes(listed as Companion)) return listed as Companion;
  if (present.length > 0) return present[0];
  if (listed === "image" || listed === "music" || listed === "city" || listed === "building" || listed === "film" || listed === "book") {
    return listed;
  }
  return "";
}

async function previousCompanion(
  admin: ReturnType<typeof createClient>,
  userId: string,
  letterDate: string,
): Promise<Companion | ""> {
  const { data } = await admin
    .from("daily_letters")
    .select("forms, image_url, music_title, city_name, building_name, film_title, book_title")
    .eq("user_id", userId)
    .lt("letter_date", letterDate)
    .order("letter_date", { ascending: false })
    .limit(8);
  for (const row of data ?? []) {
    const found = readCompanion(row as Record<string, unknown>);
    if (found) return found;
  }
  return "";
}

async function draftWithNano(
  apiKey: string,
  profile: Profile,
  posts: string[],
  signals: Signal[],
  observedNote: string,
  explore: boolean,
  forms: string[],
  previous: PreviousLetter[],
  strict: boolean,
): Promise<Draft> {
  const raw = await complete(apiKey, NANO, [
    {
      role: "system",
      content:
        "You are writing tomorrow's museum letter for one person. Return JSON only, with no explanation. Write every text field in English. " +
        "person is the portrait they filled in. Use every field that has content. Do not invent missing facts, and do not rewrite those fields. " +
        "recent_signals are later saves, likes, and notes. They are newer than the declared hobbies. When they disagree, follow the behavior. " +
        "observed_note is only a direction inferred from behavior. You may use it, but do not turn it into a new list of hobbies. " +
        "Do not reuse any keyword or quote in avoid, and do not keep one with only a word or two changed. Each time, choose another concrete facet of the portrait, such as a material, place, sound, work, or kind of light. " +
        (strict ? "The previous keyword is still in avoid. This keyword must be a new phrase. " : "") +
        "When explore is true, do not repeat the declared hobbies and do not stay on the direction already named in observed_note. Draw an adjacent direction they have not shown yet, and write it as a first meeting. " +
        "Always fill keyword and quote. Also fill only the one rotating piece named in forms. Leave every other field as an empty string. " +
        "keyword is one to four English words. Do not use blank or margin unless avoid does not already contain them and the portrait has no other concrete thing. " +
        "quote is one new English sentence, with no quotation marks. quote_author is a real author only when the sentence is a well-known line they actually wrote. Otherwise it must be an empty string. Never invent an author. " +
        companionBrief(forms),
    },
    {
      role: "user",
      content: JSON.stringify({
        forms,
        person: personOf(profile),
        recent_posts: posts,
        recent_signals: signals,
        observed_note: observedNote,
        avoid: previous,
        explore,
      }),
    },
  ], 500, true, 0.9);
  const parsed = readObject(raw);
  const draft = {
    keyword: cleanSentence(parsed.keyword, 40),
    quote: cleanSentence(parsed.quote, 180),
    quoteAuthor: cleanSentence(parsed.quote_author, 24),
    musicTitle: cleanSentence(parsed.music_title, 80),
    musicArtist: cleanSentence(parsed.music_artist, 60),
    imageBrief: cleanSentence(parsed.image_brief, 400),
    cityName: cleanSentence(parsed.city_name, 80),
    cityCountry: cleanSentence(parsed.city_country, 60),
    buildingName: cleanSentence(parsed.building_name, 80),
    buildingCity: cleanSentence(parsed.building_city, 60),
    filmTitle: cleanSentence(parsed.film_title, 80),
    filmDirector: cleanSentence(parsed.film_director, 60),
    bookTitle: cleanSentence(parsed.book_title, 80),
    bookAuthor: cleanSentence(parsed.book_author, 60),
  };
  const useful = Boolean(
    draft.keyword || draft.quote || draft.musicTitle || draft.imageBrief ||
      draft.cityName || draft.buildingName || draft.filmTitle || draft.bookTitle,
  );
  if (!useful) throw new Error("nano json empty");
  return draft;
}

async function whyWithUltra(
  apiKey: string,
  draft: Draft,
  profile: Profile,
  signals: Signal[],
  observedNote: string,
  explore: boolean,
  forms: string[],
): Promise<string> {
  const raw = await complete(apiKey, ULTRA, [
    {
      role: "system",
      content:
        "Return JSON only: {\"why_today\":\"one English sentence\"}. " +
        "person is what they wrote about themselves. When there is no behavior, say why tomorrow's letter fits this person, using a place, school, bio, or personality field that actually has content. " +
        "When recent_signals is not empty and explore is not true, name one concrete piece of evidence and say why the letter follows that new direction. Do not merely repeat the hobbies. " +
        "When explore is true, say this is an adjacent direction they have not shown yet, and tie it to one line from the signals. Do not say they already like that direction. " +
        "If the letter includes a song, place, building, film, or book, you may name it as the concrete thing that fits, still grounded in one real detail from the person or the signals. " +
        "No quotation marks, no signature, and do not recite the profile field by field.",
    },
    {
      role: "user",
      content: JSON.stringify({
        forms,
        person: personOf(profile),
        letter: draft,
        recent_signals: signals,
        observed_note: observedNote,
        explore,
      }),
    },
  ], 220, true);
  return cleanSentence(readObject(raw).why_today, 220);
}

async function paintLetter(
  admin: ReturnType<typeof createClient>,
  falKey: string,
  userId: string,
  letterDate: string,
  prompt: string,
): Promise<string> {
  if (!falKey) return "";
  try {
    const bytes = await paint(falKey, prompt);
    const path = `${userId}/letters/${letterDate}-${Date.now()}.jpg`;
    const file = new Blob([bytes], { type: "image/jpeg" });
    const { error } = await admin.storage.from("post_images").upload(path, file, {
      contentType: "image/jpeg",
      upsert: false,
    });
    if (error) return "";
    return admin.storage.from("post_images").getPublicUrl(path).data.publicUrl;
  } catch (error) {
    console.log("letter image failed", error instanceof Error ? error.name : "error");
    return "";
  }
}

async function paint(apiKey: string, prompt: string): Promise<Uint8Array> {
  const response = await fetch(FAL_SCHNELL, {
    method: "POST",
    headers: {
      Authorization: `Key ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      prompt,
      image_size: "square_hd",
      num_images: 1,
      output_format: "jpeg",
      enable_safety_checker: true,
    }),
    signal: AbortSignal.timeout(45_000),
  });
  if (!response.ok) throw new Error(`fal ${response.status}`);
  const data = await response.json();
  const url = data?.images?.[0]?.url;
  if (typeof url !== "string" || !url.startsWith("https://")) {
    throw new Error("fal url missing");
  }
  const image = await fetch(url, { signal: AbortSignal.timeout(20_000) });
  if (!image.ok) throw new Error(`image download ${image.status}`);
  const bytes = new Uint8Array(await image.arrayBuffer());
  if (bytes.length < 32 || bytes.length > 8_000_000) throw new Error("image size");
  return bytes;
}

async function complete(
  apiKey: string,
  model: string,
  messages: { role: string; content: string }[],
  maxTokens: number,
  disableThinking: boolean,
  temperature = 0.4,
): Promise<string> {
  const urls = model === ULTRA
    ? [
      "https://api.tokenfactory.nebius.com/v1/chat/completions",
      "https://api.tokenfactory.us-central1.nebius.com/v1/chat/completions",
    ]
    : [
      "https://api.tokenfactory.nebius.com/v1/chat/completions",
      "https://api.tokenfactory.eu-north1.nebius.com/v1/chat/completions",
    ];
  const post = (url: string, thinkingOff: boolean) => {
    const body: Record<string, unknown> = {
      model,
      messages,
      temperature,
      max_tokens: maxTokens,
    };
    if (thinkingOff) {
      body.extra_body = { chat_template_kwargs: { enable_thinking: false } };
    }
    return fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(50_000),
    });
  };

  let response: Response | null = null;
  let lastStatus = 0;
  for (const url of urls) {
    response = await post(url, disableThinking);
    lastStatus = response.status;
    if (response.ok) break;
    if (disableThinking && response.status >= 400 && response.status < 500) {
      response = await post(url, false);
      lastStatus = response.status;
      if (response.ok) break;
    }
    if (response.status !== 404) break;
  }
  if (!response?.ok) throw new Error(`token factory ${lastStatus}`);
  const data = await response.json();
  const message = data?.choices?.[0]?.message ?? {};
  const content = textOf(message.content) ||
    textOf(message.reasoning_content) ||
    textOf(message.reasoning);
  if (!content.trim()) throw new Error("empty completion");
  return content;
}

function textOf(value: unknown): string {
  if (typeof value === "string") return value;
  if (!Array.isArray(value)) return "";
  return value.map((part) => {
    if (typeof part === "string") return part;
    if (part && typeof part === "object" && "text" in part) {
      return String((part as { text?: unknown }).text ?? "");
    }
    return "";
  }).join("");
}

function readObject(raw: string): Record<string, unknown> {
  const stripped = raw.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  const source = stripped.includes("{") ? stripped : raw;
  const start = source.indexOf("{");
  const end = source.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no json");
  const parsed = JSON.parse(source.slice(start, end + 1));
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("json not object");
  }
  return parsed as Record<string, unknown>;
}

function cleanSentence(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  let text = value.trim();
  const wraps = new Set(['"', "'", "“", "”", "「", "」", "『", "』"]);
  while (text.length >= 2 && wraps.has(text[0]) && wraps.has(text[text.length - 1])) {
    text = text.slice(1, -1).trim();
  }
  return [...text].slice(0, max).join("");
}
