import { serve } from "https://deno.land/std@0.182.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { stringify } from "https://deno.land/std@0.182.0/encoding/yaml.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*"
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const data: {
    proxies: unknown[];
    "proxy-groups": unknown[];
    rules: string[];
    "rule-providers": Record<string, unknown>;
  } = {
    proxies: [],
    "proxy-groups": [],
    rules: [],
    "rule-providers": {},
  };

  const [{ data: proxies }, { data: rules }, { data: ruleProviders }] =
    await Promise.all([
      supabase.from("proxies").select("*").order("id"),
      supabase.from("rules").select("*").order("sort").order("id"),
      supabase.from("rule_providers").select("*").order("id"),
    ]);

  proxies?.forEach((proxy) => {
    data.proxies.push(proxy.metadata);
  });

  data["proxy-groups"].push({
    name: "Proxy",
    type: "select",
    proxies: proxies?.map((proxy) => proxy.id) || [],
  });

  ruleProviders?.forEach((provider) => {
    data["rule-providers"][provider.id] = provider.metadata;
  });

  rules?.forEach((rule) => {
    data.rules.push(
      `${rule.keyword},${rule.value ? `${rule.value},` : ""}${rule.policy}`,
    );
  });

  return new Response(
    stringify(data),
    { headers: { "Content-Type": "application/x-yaml", ...corsHeaders } },
  );
});
