// 按用户画像给首页帖子排序。打开首页时调用一次，同一天不重复叫模型。
// 只使用 Nano。失败则让客户端保持原来的顺序。

import { createClient } from "npm:@supabase/supabase-js@2";

const NANO = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B";

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
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ error: "只接受 POST。" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) return json({ error: "请先登录。" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const nebiusKey = Deno.env.get("NEBIUS_API_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey || !nebiusKey) {
    return json({ error: "首页还没有排好。" }, 500);
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
  const feedDate = typeof payload.feed_date === "string" ? payload.feed_date.trim() : "";
  if (!allowedDate(feedDate)) return json({ error: "这一天不能排序。" }, 400);

  const admin = createClient(supabaseUrl, serviceKey);
  const posts = await publicPosts(admin);
  if (posts.length === 0) return json({ ids: [], cached: true });

  const profile = await readProfile(admin, userId);
  const signals = await readSignals(admin, userId);
  const portraitStamp = hashText(JSON.stringify({ person: profile.person, note: profile.observedNote, stamp: profile.interestStamp }));
  const catalogStamp = hashText(posts.map((post) => post.id).join(","));

  const { data: cached } = await admin
    .from("feed_ranks")
    .select("feed_date, portrait_stamp, catalog_stamp, post_ids")
    .eq("user_id", userId)
    .maybeSingle();
  const cachedIds = Array.isArray(cached?.post_ids) ? cached.post_ids.map((id: unknown) => String(id)) : [];
  const sameDay = String(cached?.feed_date ?? "").slice(0, 10) === feedDate;
  if (
    sameDay &&
    cached?.portrait_stamp === portraitStamp &&
    cached?.catalog_stamp === catalogStamp &&
    cachedIds.length > 0
  ) {
    return json({ ids: cachedIds, cached: true });
  }

  let ranked: string[] = [];
  try {
    ranked = await rankWithNano(nebiusKey, profile, signals, posts);
  } catch (error) {
    console.log("rank failed", error instanceof Error ? error.name : "error");
    return json({ error: "首页还没有排好。" }, 502);
  }
  if (ranked.length === 0) return json({ error: "首页还没有排好。" }, 502);

  const { error: writeError } = await admin.from("feed_ranks").upsert({
    user_id: userId,
    feed_date: feedDate,
    portrait_stamp: portraitStamp,
    catalog_stamp: catalogStamp,
    post_ids: ranked,
  }, { onConflict: "user_id" });
  if (writeError) return json({ ids: ranked, cached: false });
  return json({ ids: ranked, cached: false });
});

type PostCard = { id: string; keywords: string[]; text: string };
type ProfileCard = { person: Record<string, string>; observedNote: string; interestStamp: string };

function allowedDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const target = Date.parse(`${value}T00:00:00Z`);
  if (Number.isNaN(target)) return false;
  const now = new Date();
  const utc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const delta = Math.round((target - utc) / 86_400_000);
  return delta >= -1 && delta <= 1;
}

function hashText(text: string): string {
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = (Math.imul(hash, 33) + text.charCodeAt(i)) >>> 0;
  }
  return hash.toString(16);
}

function clip(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return [...value.trim()].slice(0, max).join("");
}

async function publicPosts(admin: ReturnType<typeof createClient>): Promise<PostCard[]> {
  const { data } = await admin
    .from("inspirations")
    .select("id, user_text, quote, keywords, is_private, is_public")
    .order("created_at", { ascending: false })
    .limit(48);
  const posts: PostCard[] = [];
  for (const row of data ?? []) {
    if (row.is_private === true || row.is_public === false) continue;
    const id = typeof row.id === "string" ? row.id : "";
    if (!id) continue;
    const raw = typeof row.user_text === "string" ? row.user_text : "";
    const parts = raw.split("\u001e");
    const title = parts.length > 1 ? parts[0] : "";
    const body = parts.length > 1 ? parts.slice(1).join("") : raw;
    const keywords = Array.isArray(row.keywords)
      ? row.keywords.map((item: unknown) => clip(String(item), 16)).filter((item: string) => item).slice(0, 4)
      : [];
    const text = [title, body, typeof row.quote === "string" ? row.quote : ""]
      .map((item) => item.trim())
      .filter((item) => item.length > 0)
      .join(" / ");
    posts.push({ id, keywords, text: clip(text, 80) });
  }
  return posts;
}

async function readProfile(admin: ReturnType<typeof createClient>, userId: string): Promise<ProfileCard> {
  const { data } = await admin
    .from("profiles")
    .select("username, age, gender, location, school, bio, hobbies, personality, occupation, observed_note, interest_stamp")
    .eq("id", userId)
    .maybeSingle();
  const row = data ?? {};
  const person: Record<string, string> = {
    name: clip(row.username, 32),
    bio: clip(row.bio, 80),
    age: clip(row.age == null ? "" : String(row.age), 8),
    gender: clip(row.gender, 16),
    location: clip(row.location, 24),
    school: clip(row.school, 40),
    hobbies: clip(row.hobbies, 80),
    personality: clip(row.personality, 40),
    occupation: clip(row.occupation, 40),
  };
  return {
    person: Object.fromEntries(Object.entries(person).filter((entry) => entry[1].trim().length > 0)),
    observedNote: clip(row.observed_note, 80),
    interestStamp: typeof row.interest_stamp === "string" ? row.interest_stamp.trim() : "",
  };
}

async function readSignals(admin: ReturnType<typeof createClient>, userId: string): Promise<string[]> {
  const { data } = await admin
    .from("interest_signals")
    .select("kind, excerpt")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(6);
  const lines: string[] = [];
  for (const row of data ?? []) {
    const excerpt = clip(row.excerpt, 80);
    if (!excerpt) continue;
    const kind = row.kind === "save" ? "收藏" : row.kind === "like" ? "点赞" : "写下";
    lines.push(`${kind} ${excerpt}`);
  }
  return lines;
}

async function rankWithNano(
  apiKey: string,
  profile: ProfileCard,
  signals: string[],
  posts: PostCard[],
): Promise<string[]> {
  const raw = await complete(apiKey, [
    {
      role: "system",
      content:
        "你在为一个人排博物馆首页。只返回 JSON：{\"ids\":[\"帖子id\"]}。" +
        "person 是他自己填写的画像。observed_note 和 recent_signals 是后来的兴趣，比填写的爱好更优先。" +
        "把最可能想看的放在前面。没有近期行为时，按画像里有内容的字段来排。" +
        "大约两成位置留给画像里还没写过、但和已有兴趣相邻的帖子。" +
        "只能使用给出的 id，不要编造。最多 24 个，不要重复。",
    },
    {
      role: "user",
      content: JSON.stringify({
        person: profile.person,
        observed_note: profile.observedNote,
        recent_signals: signals,
        posts,
      }),
    },
  ]);
  const parsed = readObject(raw);
  const known = new Set(posts.map((post) => post.id));
  const ordered: string[] = [];
  const seen = new Set<string>();
  const ids = Array.isArray(parsed.ids) ? parsed.ids : [];
  for (const item of ids) {
    const id = typeof item === "string" ? item.trim() : "";
    if (!known.has(id) || seen.has(id)) continue;
    seen.add(id);
    ordered.push(id);
    if (ordered.length >= 24) break;
  }
  const minimum = Math.min(4, posts.length);
  if (ordered.length < minimum) throw new Error("rank short");
  return ordered;
}

async function complete(
  apiKey: string,
  messages: { role: string; content: string }[],
): Promise<string> {
  const urls = [
    "https://api.tokenfactory.nebius.com/v1/chat/completions",
    "https://api.tokenfactory.eu-north1.nebius.com/v1/chat/completions",
  ];
  const post = (url: string, thinkingOff: boolean) => {
    const body: Record<string, unknown> = {
      model: NANO,
      messages,
      temperature: 0.3,
      max_tokens: 700,
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
    response = await post(url, true);
    lastStatus = response.status;
    if (response.ok) break;
    if (response.status >= 400 && response.status < 500) {
      response = await post(url, false);
      lastStatus = response.status;
      if (response.ok) break;
    }
    if (response.status !== 404) break;
  }
  if (!response?.ok) throw new Error(`token factory ${lastStatus}`);
  const data = await response.json();
  const message = data?.choices?.[0]?.message ?? {};
  const content = textOf(message.content) || textOf(message.reasoning_content) || textOf(message.reasoning);
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
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("json not object");
  return parsed as Record<string, unknown>;
}
