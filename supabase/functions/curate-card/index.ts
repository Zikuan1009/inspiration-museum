// 策展接口。App 只提交标题和正文。
// Nano 失败则整次失败，不改叫 Ultra。Ultra 失败则退回 Nano 的文字。
// 画图失败则只返回文字，图片仍由用户自己选。

import { createClient } from "npm:@supabase/supabase-js@2";

const NANO = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B";
const ULTRA = "nvidia/Nemotron-3-Ultra-550b-a55b";
const FAL_SCHNELL = "https://fal.run/fal-ai/flux/schnell";

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

type NanoCard = {
  keywords: string[];
  quote: string;
  imageBrief: string;
  needsUltra: boolean;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Only POST is accepted." }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ error: "Sign in first." }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !anonKey) {
    return json({ error: "Curation is not configured." }, 500);
  }

  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Sign in first." }, 401);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Write a title or some text first." }, 400);
  }

  const title = clip(payload.title, 80);
  const text = clip(payload.text ?? payload.body, 2000);
  const deep = payload.deep === true;
  if (!title && !text) {
    return json({ error: "Write a title or some text first." }, 400);
  }

  const nebiusKey = Deno.env.get("NEBIUS_API_KEY") ?? "";
  if (!nebiusKey) {
    return json({ error: "Curation is not configured." }, 500);
  }

  let nano: NanoCard;
  try {
    nano = await curateWithNano(nebiusKey, title, text);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "error";
    console.log("nano failed", detail);
    return json({ error: publicFailure(detail) }, 502);
  }

  let imageBrief = nano.imageBrief;
  let caption = "";
  let usedUltra = false;
  if (deep || nano.needsUltra) {
    try {
      const ultra = await curateWithUltra(nebiusKey, title, text, nano);
      if (ultra.imageBrief) imageBrief = ultra.imageBrief;
      caption = ultra.caption;
      usedUltra = true;
    } catch (error) {
      console.log(
        "ultra failed",
        error instanceof Error ? error.name : "error",
      );
    }
  }

  let imageUrl: string | null = null;
  let imagePath: string | null = null;
  let imageError: string | null = null;
  const falKey = Deno.env.get("FAL_KEY") ?? "";
  if (!imageBrief) {
    imageError = "No scene came back to paint. You can choose an image instead.";
  } else if (!falKey) {
    imageError = "Image generation is not configured.";
  } else {
    try {
      const bytes = await paint(falKey, imageBrief);
      const path = `${userData.user.id}/${crypto.randomUUID()}.jpg`;
      const file = new Blob([bytes], { type: "image/jpeg" });
      let uploadError = (await supabase.storage.from("post_images").upload(
        path,
        file,
        { contentType: "image/jpeg", upsert: false },
      )).error;
      if (uploadError) {
        const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
        if (!serviceKey) throw uploadError;
        const admin = createClient(supabaseUrl, serviceKey);
        uploadError = (await admin.storage.from("post_images").upload(
          path,
          file,
          { contentType: "image/jpeg", upsert: false },
        )).error;
      }
      if (uploadError) throw uploadError;
      imagePath = path;
      imageUrl = supabase.storage.from("post_images").getPublicUrl(path).data
        .publicUrl;
    } catch (error) {
      const detail = error instanceof Error
        ? error.message
        : typeof error === "object" && error && "message" in error
        ? String((error as { message: unknown }).message)
        : "error";
      console.log("image failed", detail);
      imageError = imageFailure(detail);
    }
  }

  return json({
    keywords: nano.keywords,
    quote: nano.quote,
    image_brief: imageBrief,
    caption,
    needs_ultra: nano.needsUltra,
    used_ultra: usedUltra,
    image_url: imageUrl,
    image_path: imagePath,
    image_error: imageError,
    models: { fast: NANO, deep: usedUltra ? ULTRA : null },
  });
});

function clip(value: unknown, max: number): string {
  const text = typeof value === "string" ? value.trim() : "";
  return [...text].slice(0, max).join("");
}

async function curateWithNano(
  apiKey: string,
  title: string,
  text: string,
): Promise<NanoCard> {
  const raw = await complete(
    apiKey,
    NANO,
    [
      {
        role: "system",
        content:
          'You are a curator at Inspiration Museum. Return one valid JSON object only, with no Markdown and no explanation, exactly in this shape: {"keywords": ["word", "word"], "quote": "sentence", "image_brief": "scene", "needs_ultra": false}. Every string value must be wrapped in double quotes. keywords is an array of 2 to 4 short English words. quote is one English sentence; the sentence itself contains no quotation marks. image_brief is a concrete visible scene in English, with no text, watermark, or logo in the picture. needs_ultra is true only when the writing is too vague to form a clear picture.',
      },
      {
        role: "user",
        content: `标题：${title || "（无）"}\n正文：${text || "（无）"}`,
      },
    ],
    700,
    true,
  );
  const parsed = readObject(raw);
  const keywords = cleanKeywords(parsed.keywords);
  const quote = cleanSentence(parsed.quote, 120);
  const imageBrief = cleanSentence(
    parsed.image_brief ?? parsed.imageBrief ?? parsed.image_prompt ??
      parsed.visual_prompt ?? parsed["画面说明"],
    800,
  );
  if (keywords.length === 0 || !quote) {
    throw new Error("nano json incomplete");
  }
  return {
    keywords,
    quote,
    imageBrief,
    needsUltra: parsed.needs_ultra === true || parsed.needs_ultra === "true",
  };
}

async function curateWithUltra(
  apiKey: string,
  title: string,
  text: string,
  nano: NanoCard,
): Promise<{ imageBrief: string; caption: string }> {
  const raw = await complete(
    apiKey,
    ULTRA,
    [
      {
        role: "system",
        content:
          'You are a senior curator at Inspiration Museum. Return one valid JSON object only, with no Markdown and no explanation, exactly in this shape: {"image_brief": "scene", "caption": "sentence"}. Every string value must be wrapped in double quotes. image_brief is a rewritten English scene, more concrete than the draft, with no text, watermark, or logo in the picture. caption is one English sentence about the piece; the sentence itself contains no quotation marks.',
      },
      {
        role: "user",
        content:
          `标题：${title || "（无）"}\n正文：${text || "（无）"}\n初稿关键词：${
            nano.keywords.join("、")
          }\n初稿引言：${nano.quote}\n初稿画面：${nano.imageBrief}`,
      },
    ],
    900,
    false,
  );
  const parsed = readObject(raw);
  const imageBrief = cleanSentence(parsed.image_brief, 800);
  const caption = cleanSentence(parsed.caption, 160);
  if (!imageBrief && !caption) throw new Error("ultra json empty");
  return { imageBrief, caption };
}

async function complete(
  apiKey: string,
  model: string,
  messages: { role: string; content: string }[],
  maxTokens: number,
  disableThinking: boolean,
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
      temperature: 0.4,
      max_tokens: maxTokens,
    };
    if (thinkingOff) {
      body.extra_body = {
        chat_template_kwargs: { enable_thinking: false },
      };
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

  // 限流、5xx 和网络错误是暂时的：换下一个区域，全部失败时再整轮重试一次。
  const transient = (status: number) =>
    status === 0 || status === 404 || status === 429 || status >= 500;
  let response: Response | null = null;
  let lastStatus = 0;
  outer: for (let round = 0; round < 2; round++) {
    if (round > 0) await new Promise((r) => setTimeout(r, 800));
    for (const url of urls) {
      try {
        response = await post(url, disableThinking);
        lastStatus = response.status;
        if (response.ok) break outer;
        if (
          disableThinking && response.status >= 400 && response.status < 500 &&
          response.status !== 404 && response.status !== 429
        ) {
          response = await post(url, false);
          lastStatus = response.status;
          if (response.ok) break outer;
        }
      } catch (error) {
        const name = error instanceof Error ? error.name : "error";
        console.log("token factory fetch", name);
        if (name === "TimeoutError" || name === "AbortError") {
          throw new Error("token factory timeout");
        }
        response = null;
        lastStatus = 0;
      }
      if (!transient(lastStatus)) break outer;
    }
  }
  if (!response || !response.ok) {
    console.log("token factory status", lastStatus);
    throw new Error(`token factory ${lastStatus}`);
  }

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

function imageFailure(detail: string): string {
  if (detail.includes("401") || detail.includes("403")) {
    return "The image service refused the request.";
  }
  if (detail.includes("404")) return "The image model was not found.";
  if (detail.toLowerCase().includes("timeout") || detail.includes("abort")) {
    return "Painting took too long. Try again or choose an image.";
  }
  if (
    detail.toLowerCase().includes("row-level") ||
    detail.toLowerCase().includes("unauthorized") ||
    detail.includes("权限")
  ) {
    return "The image was painted but could not be saved.";
  }
  return "The image could not be generated. Try again or choose an image.";
}

function publicFailure(detail: string): string {
  if (detail.includes("401") || detail.includes("403")) {
    return "The curation service refused the request.";
  }
  if (detail.includes("404")) return "The curation model was not found.";
  if (detail.includes("empty") || detail.toLowerCase().includes("json")) {
    return "The model did not return a usable card. Try again.";
  }
  if (detail.toLowerCase().includes("timeout") || detail.includes("abort")) {
    return "Curation took too long. Try again.";
  }
  return "Curation did not finish. Try again.";
}

function readObject(raw: string): Record<string, unknown> {
  const stripped = raw.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  const source = stripped.includes("{") ? stripped : raw;
  const start = source.indexOf("{");
  const end = source.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("no json");
  const body = source.slice(start, end + 1);
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    // 模型有时把字符串值的引号省掉（"quote": Walking home, ...），按键名切开再取值。
    parsed = looseObject(body);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("json not object");
  }
  return parsed as Record<string, unknown>;
}

function looseObject(body: string): Record<string, unknown> {
  const inner = body.slice(1, -1);
  const keys = [...inner.matchAll(/"([A-Za-z_]+)"\s*:/g)];
  if (keys.length === 0) throw new Error("json unreadable");
  const out: Record<string, unknown> = {};
  keys.forEach((match, i) => {
    const from = (match.index ?? 0) + match[0].length;
    const to = i + 1 < keys.length ? keys[i + 1].index ?? inner.length : inner.length;
    let raw = inner.slice(from, to).trim().replace(/,\s*$/, "").trim();
    if (raw === "true" || raw === "false") {
      out[match[1]] = raw === "true";
      return;
    }
    if (raw.startsWith("[") || raw.startsWith('"')) {
      try {
        out[match[1]] = JSON.parse(raw);
        return;
      } catch {
        raw = raw.replace(/^[\["]+|[\]"]+$/g, "");
      }
    }
    out[match[1]] = raw;
  });
  return out;
}

function cleanKeywords(value: unknown): string[] {
  const list = Array.isArray(value)
    ? value
    : typeof value === "string"
    ? (/[、,，/|×]/.test(value)
      ? value.split(/[、,，/|×]/)
      : value.trim().split(/\s+/))
    : [];
  const out: string[] = [];
  for (const item of list) {
    if (typeof item !== "string") continue;
    const word = [...item.trim().replace(/^["']+|["']+$/g, "").replace(/\s+/g, " ")]
      .slice(0, 20).join("").trim();
    if (!word || out.includes(word)) continue;
    out.push(word);
    if (out.length === 4) break;
  }
  return out;
}

function cleanSentence(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  let text = value.trim();
  const wraps = new Set(['"', "'", "“", "”", "「", "」", "『", "』"]);
  while (
    text.length >= 2 &&
    wraps.has(text[0]) &&
    wraps.has(text[text.length - 1])
  ) {
    text = text.slice(1, -1).trim();
  }
  return [...text].slice(0, max).join("");
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
  if (bytes.length < 32 || bytes.length > 8_000_000) {
    throw new Error("image size");
  }
  return bytes;
}
